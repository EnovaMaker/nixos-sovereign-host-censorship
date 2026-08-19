{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.sovereign.sso;
  domain = cfg.domain;

  # Authelia (nixpkgs 24.05) is configured via services.authelia.instances.*
  secretFile = name: key: pkgs.writeText name key;
  oidcKeyPem = pkgs.runCommand "authelia-oidc-key.pem" { } ''
    ${pkgs.openssl}/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$out" 2>/dev/null
  '';
in
{
  options.services.sovereign.sso = {
    enable = mkEnableOption "OIDC/SSO identity provider (Authelia)";

    provider = mkOption {
      type = types.enum [ "authelia" ];
      default = "authelia";
      description = "SSO provider. Reserved for future multi-provider support — nixpkgs 24.05 ships Authelia only, and this module currently hardcodes the Authelia config below regardless of this option's value.";
    };

    domain = mkOption {
      type = types.str;
      default = "sso.localhost";
      description = "Domain for SSO services";
    };

    adminEmail = mkOption {
      type = types.str;
      default = "admin@${domain}";
      description = "Admin email";
    };

    enableTls = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TLS";
    };

    secretKey = mkOption {
      type = types.str;
      default = "";
      description = "Secret key for signing (use sops-nix/agenix in production; generated files keep it out of NixOS config)";
    };

    database.type = mkOption {
      type = types.enum [ "sqlite" "postgresql" ];
      default = "sqlite";
      description = "Database type";
    };

    database.host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Database host";
    };

    database.port = mkOption {
      type = types.port;
      default = 5432;
      description = "Database port";
    };

    database.name = mkOption {
      type = types.str;
      default = "authelia";
      description = "Database name";
    };

    database.user = mkOption {
      type = types.str;
      default = "authelia";
      description = "Database user";
    };

    database.password = mkOption {
      type = types.str;
      default = "";
      description = "Database password";
    };

    applications = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          slug = mkOption {
            type = types.str;
            description = "Application slug (used as OIDC client id)";
          };
          name = mkOption {
            type = types.str;
            description = "Application display name";
          };
          providerType = mkOption {
            type = types.enum [ "oauth2" "saml" "ldap" "proxy" ];
            default = "oauth2";
            description = "Authentication provider type. NOT YET WIRED — every application is unconditionally registered as an OIDC client below, regardless of this value.";
          };
          redirectUris = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "OAuth2 redirect URIs";
          };
          launchUrl = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Application launch URL";
          };
          secret = mkOption {
            type = types.str;
            description = ''
              OIDC client secret for this application (Authelia requires every
              confidential client to have one — use a sops-nix/agenix secret
              in production; a hardcoded value here is for testing only).
            '';
          };
        };
      });
      default = {
        matrix = {
          slug = "matrix";
          name = "Matrix";
          redirectUris = [ "https://matrix.localhost/_synapse/client/oidc/callback" ];
          launchUrl = "https://matrix.localhost";
          # Real hash for the plaintext "insecure_secret", generated with
          # `authelia crypto hash generate pbkdf2 --password insecure_secret`
          # against the actual authelia-4.37.5 binary — test-only, replace
          # via sops-nix/agenix in production.
          secret = "$pbkdf2-sha512$310000$5eilVKoVO3gdkzP15wrIUg$RScoDnfBCMFLtAkMo3toadqpGSXtoytvLbtHbbzEA7rPTe4QbehV5V964iP0tOWKtGtXZcsfC28uEVM1dWQ6Ow";
        };
        grafana = {
          slug = "grafana";
          name = "Grafana";
          redirectUris = [ "https://monitoring.localhost/login/generic_oauth" ];
          launchUrl = "https://monitoring.localhost";
          # Same real hash as above (also for "insecure_secret") — test-only.
          secret = "$pbkdf2-sha512$310000$5eilVKoVO3gdkzP15wrIUg$RScoDnfBCMFLtAkMo3toadqpGSXtoytvLbtHbbzEA7rPTe4QbehV5V964iP0tOWKtGtXZcsfC28uEVM1dWQ6Ow";
        };
      };
      description = "OIDC applications to provision";
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = cfg.secretKey != "";
      message = ''
        services.sovereign.sso.secretKey must be set. In production use a
        sops-nix/agenix secret; for testing any non-empty string works.
      '';
    }];

    services.authelia.instances.main.enable = true;

    services.authelia.instances.main.secrets = {
      jwtSecretFile = secretFile "authelia-jwt-secret" cfg.secretKey;
      storageEncryptionKeyFile = secretFile "authelia-storage-key" cfg.secretKey;
      oidcHmacSecretFile = secretFile "authelia-oidc-hmac" cfg.secretKey;
      oidcIssuerPrivateKeyFile = oidcKeyPem;
    };

    # Schema below targets Authelia 4.37.5 specifically (the version nixpkgs
    # 24.05 actually ships) — its config schema predates the 4.38 "address"
    # unification (server.host/port, not server.address) and the multi-cookie
    # session refactor (session.domain, not session.cookies[] list). Bump
    # this comment (and the schema) if the nixpkgs pin ever moves past 4.38.
    services.authelia.instances.main.settings = {
        theme = "dark";
        log.level = "info";
        server.host = "127.0.0.1";
        server.port = 9091;

        storage.local = mkIf (cfg.database.type == "sqlite") {
          # /var/lib/authelia-main, not /var/lib/authelia: the nixpkgs
          # authelia module names systemd's StateDirectory after the
          # instance ("main"), and ProtectSystem=strict makes every other
          # path read-only — writing anywhere else fails at startup.
          path = "/var/lib/authelia-main/db.sqlite3";
        };

        storage.postgres = mkIf (cfg.database.type == "postgresql") {
          host = cfg.database.host;
          port = cfg.database.port;
          database = cfg.database.name;
          username = cfg.database.user;
          password = cfg.database.password;
        };

        authentication_backend.file = {
          path = "/var/lib/authelia-main/users.yml";
        };

        access_control.default_policy = "deny";
        access_control.rules = lib.flatten (lib.mapAttrsToList (name: app: [{
          domain = (builtins.elemAt (builtins.match "https?://(.+)" (app.launchUrl or "https://${name}.${domain}")) 0);
          policy = "one_factor";
          resources = [ ".*" ];
        }]) cfg.applications);

        # session.secret is a plain settings value (not routed through
        # `secrets.*File`), so no double-definition conflict here.
        session = {
          secret = cfg.secretKey;
          domain = domain;
          same_site = "lax";
        };

        identity_providers.oidc = {
          # hmac_secret / issuer_private_key are intentionally NOT set here —
          # they're already supplied via `secrets.oidcHmacSecretFile` /
          # `secrets.oidcIssuerPrivateKeyFile` above. Setting both the
          # secrets-file AND a literal settings value for the same key is
          # rejected by Authelia at startup ("it's already defined in other
          # configuration sources") — this cost real VM-test debugging time.
          #
          # cors.allowed_origins (not cors.endpoints — `endpoints` is a
          # different option that whitelists which OIDC endpoint *names*
          # ("authorization"/"token"/"introspection"/"revocation"/"userinfo")
          # permit CORS at all, not which origins are allowed).
          cors.allowed_origins = [ "https://${domain}" ];
          clients = lib.mapAttrsToList (name: app: {
            id = app.slug;
            description = app.name;
            secret = app.secret;
            public = false;
            authorization_policy = "one_factor";
            redirect_uris = app.redirectUris;
            scopes = [ "openid" "profile" "email" "groups" ];
          }) cfg.applications;
        };

        notifier.filesystem = {
          filename = "/var/lib/authelia-main/notifications.yml";
        };
      };

    security.acme = mkIf cfg.enableTls {
      acceptTerms = true;
      defaults.email = cfg.adminEmail;
    };

    services.nginx = mkIf cfg.enableTls {
      enable = true;
      virtualHosts."${domain}" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:9091";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 9091 ];
  };
}