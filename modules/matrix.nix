{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.sovereign.matrix;
  domain = cfg.domain;
in
{
  options.services.sovereign.matrix = {
    enable = mkEnableOption "Matrix (Synapse/Dendrite)";

    domain = mkOption {
      type = types.str;
      default = "matrix.localhost";
      description = "Domain for Matrix server";
    };

    implementation = mkOption {
      type = types.enum [ "synapse" "dendrite" ];
      default = "synapse";
      description = "Matrix server implementation";
    };

    bridge = {
      whatsapp = {
        enable = mkEnableOption "WhatsApp bridge (mautrix-whatsapp)";
        port = mkOption {
          type = types.port;
          default = 29318;
          description = "WhatsApp bridge port";
        };
      };

      signal = {
        enable = mkEnableOption "Signal bridge (mautrix-signal)";
        port = mkOption {
          type = types.port;
          default = 29319;
          description = "Signal bridge port";
        };
      };

      telegram = {
        enable = mkEnableOption "Telegram bridge (mautrix-telegram)";
        port = mkOption {
          type = types.port;
          default = 29317;
          description = "Telegram bridge port";
        };
        environmentFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = ''
            File with TELEGRAM_API_ID/TELEGRAM_API_HASH (from
            my.telegram.org), sops/agenix-managed. Required: without real
            Telegram API app credentials the bridge cannot authenticate at
            all — nixpkgs' mautrix-telegram module has no default for
            these and won't start without them. Substituted into the
            bridge's config via the module's own envsubst mechanism, never
            written to the Nix store in plaintext.
          '';
        };
      };
    };

    sso.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable OIDC SSO authentication";
    };

    sso.providerUrl = mkOption {
      type = types.str;
      default = "https://sso.${domain}";
      description = "OIDC provider URL";
    };

    sso.clientId = mkOption {
      type = types.str;
      default = "matrix";
      description = "OIDC client ID";
    };

    sso.clientSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File with the OIDC client secret (sops-nix/agenix-managed).
        Wired via Synapse's own client_secret_path — the secret is read
        by Synapse at its own runtime and never embedded in the
        Nix-generated config, which otherwise lands world-readable in
        /nix/store. When unset, no client_secret is configured at all
        (was a literal "<sops>" placeholder previously, itself in the
        store) — the OIDC provider block is only functional once this
        is set.
      '';
    };

    sso.skipVerification = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Skip Synapse's OIDC issuer metadata validation (Synapse's own
        `skip_verification`, documented as being "to allow non-compliant
        providers, e.g. issuers not running on a secure origin"). Synapse
        unconditionally rejects a non-HTTPS issuer otherwise
        ("issuer MUST use https scheme") — found via an actual VM test:
        enableTls = false + sso.enable = true
        crashes Synapse at startup without this. Leave false in
        production (a real deployment should have TLS); set true only
        for non-TLS local/test setups.
      '';
    };

    adminEmail = mkOption {
      type = types.str;
      default = "admin@${domain}";
      description = "Admin email for TLS certificates";
    };

    enableTls = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic TLS via ACME";
    };

    extraConfig = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = "Extra Synapse/Dendrite configuration";
    };

    port = mkOption {
      type = types.port;
      default = 8448;
      description = "Matrix federation port";
    };

    clientPort = mkOption {
      type = types.port;
      default = 8008;
      description = "Matrix client-server API port";
    };

    registrationSharedSecret = mkOption {
      type = types.str;
      default = "";
      description = "Shared secret for user registration";
    };

    enableRegistration = mkOption {
      type = types.bool;
      default = false;
      description = "Enable open user registration";
    };

    turn.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable TURN server for VoIP";
    };

    turn.portRange = mkOption {
      type = types.str;
      default = "49152-49252";
      description = "TURN port range";
    };

    turn.sharedSecretFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        File with the TURN shared secret (sops-nix/agenix-managed), used
        by both Synapse (turn_shared_secret_path) and coturn
        (static-auth-secret-file) — both natively support reading the
        secret from a file at their own runtime, so it's never embedded
        in the Nix-generated config (was two literal "<sops-turn>"
        placeholders previously, both landing in /nix/store). When
        unset, TURN is enabled but not authenticated — set this before
        relying on it.
      '';
    };

    databaseType = mkOption {
      type = types.enum [ "sqlite3" "psycopg2" ];
      default = "sqlite3";
      description = "Synapse database backend (sqlite3 or psycopg2/PostgreSQL)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != "matrix.localhost" || !cfg.enableTls;
        message = "Matrix: set a real domain for TLS to work";
      }
      {
        assertion = !cfg.turn.enable || builtins.match "[0-9]+-[0-9]+" cfg.turn.portRange != null;
        message = "Matrix: turn.portRange must look like \"<low>-<high>\" (e.g. \"49152-49252\"), got \"${cfg.turn.portRange}\"";
      }
    ];

    warnings = lib.optional (cfg.bridge.whatsapp.enable || cfg.bridge.signal.enable || cfg.bridge.telegram.enable) ''
      A mautrix bridge is enabled. All three (whatsapp/signal/telegram)
      depend on libolm for Matrix-side E2EE, which nixpkgs marks insecure
      (deprecated upstream, CVE-2024-45191/2/3) and refuses to build by
      default — confirmed by an actual build attempt against each
      package, not assumed. Add
      `nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];`
      (version may drift) to your own configuration, and make an informed
      decision about the known side-channel issues before relying on it
      for cryptographic security.
    '' ++ lib.optional cfg.bridge.signal.enable ''
      services.sovereign.matrix.bridge.signal is enabled. Separately from
      the libolm issue above: in a NixOS VM test with a sandboxed/NAT'd
      network, mautrix-signal.service produced zero journal output and
      never generated its Synapse appservice registration file across 5+
      restart cycles of matrix-synapse.service (~5 minutes) — root cause
      not yet identified (suspected libsignal-ffi blocking on network
      access before logging anything). Unverified on real unrestricted
      networks (whatsapp/telegram were confirmed working in the same VM
      environment); treat signal as best-effort until confirmed working
      there.
    '' ++ lib.optional (cfg.sso.enable && cfg.sso.clientSecretFile == null) ''
      services.sovereign.matrix.sso is enabled without sso.clientSecretFile
      set. The OIDC provider is configured with no client_secret at all —
      SSO login will not work until you set this (sops-nix/agenix-managed).
    '' ++ lib.optional (cfg.turn.enable && cfg.turn.sharedSecretFile == null) ''
      services.sovereign.matrix.turn is enabled without turn.sharedSecretFile
      set. Both Synapse and coturn are configured with no shared secret at
      all — TURN is running unauthenticated, not just unconfigured. Set
      this (sops-nix/agenix-managed) before relying on it for VoIP.
    '' ++ lib.optional (cfg.sso.enable && !cfg.enableTls && !cfg.sso.skipVerification) ''
      services.sovereign.matrix.sso is enabled with enableTls = false and
      sso.skipVerification = false. Synapse unconditionally rejects a
      non-HTTPS OIDC issuer at startup ("issuer MUST use https scheme") —
      found via an actual VM test. Either enable TLS for real, or set
      sso.skipVerification = true for a deliberate non-TLS local/test
      setup (never in production).
    '';

    # Registration files are 0640. whatsapp uses a real static
    # users.groups.mautrix-whatsapp Synapse can join via SupplementaryGroups
    # (mirroring what signal's own module does for itself automatically —
    # confirmed against the actual pinned nixpkgs source, rev b134951a,
    # Dec 2024: only mautrix-signal has a registerToSynapse option there;
    # whatsapp/telegram don't). telegram's own module sets DynamicUser =
    # true, and a long chain of attempts (chmod on the file, chmod on the
    # directory too, "+"-prefixed root ExecStartPre from matrix-synapse's
    # own unit, StateDirectoryMode overrides) all failed against the exact
    # same PermissionError, confirmed via multiple real VM tests. The real
    # cause, found by adding a diagnostic `stat` to the journal and reading
    # its actual output from a real VM run: /var/lib/mautrix-telegram, as
    # seen from OUTSIDE telegram's own service (e.g. from matrix-synapse),
    # is a *symlink* to /var/lib/private/mautrix-telegram — this is how
    # systemd implements DynamicUser's StateDirectory. /var/lib/private/
    # itself is root-only (0700) BY DESIGN, specifically so unrelated
    # services can never reach a DynamicUser service's state through it.
    # No permission bits on the target file or directory can ever fix
    # this — it's a structural wall one level up, not a permission
    # setting. The only real fix is to not use DynamicUser for a service
    # another unit needs direct filesystem access to, matching what
    # whatsapp/signal already do: give telegram a real static user/group
    # (declared below) and override DynamicUser = false, then use the
    # exact same SupplementaryGroups mechanism already proven for whatsapp.
    users.users.mautrix-telegram = mkIf cfg.bridge.telegram.enable {
      isSystemUser = true;
      group = "mautrix-telegram";
      home = "/var/lib/mautrix-telegram";
    };
    users.groups.mautrix-telegram = mkIf cfg.bridge.telegram.enable { };

    systemd.services.matrix-synapse = mkIf (cfg.implementation == "synapse") {
      serviceConfig.SupplementaryGroups =
        lib.optional cfg.bridge.whatsapp.enable "mautrix-whatsapp"
        ++ lib.optional cfg.bridge.telegram.enable "mautrix-telegram";
      # Without this, SupplementaryGroups can be resolved before
      # systemd-sysusers has actually created the mautrix-whatsapp/telegram
      # group, failing the same way (exit 216/GROUP) — found via an actual
      # VM test. NixOS only adds this ordering automatically for a
      # service's own serviceConfig.User; a cross-service group reference
      # like this one needs it stated explicitly.
      after = [ "systemd-sysusers.service" ];
    };

    # nixpkgs' own preStart generates telegram-registration.yaml (with a
    # freshly-random as_token/hs_token) but the SAME --generate-registration
    # invocation also tries to write those tokens back into its --config
    # file so the long-running process has them too — that write targets an
    # immutable Nix-store path (pkgs.formats.json output), so it silently
    # fails ("Read-only file system") and the bridge crash-loops forever
    # with "appservice.as_token not configured" — confirmed via a real VM
    # test, not assumed; a genuine, separate bug from the DynamicUser/
    # symlink issue above. A later nixpkgs revision fixes this upstream by
    # rendering settings to a writable path up front (confirmed by directly
    # inspecting that revision's source); this pinned revision (b134951a,
    # Dec 2024) doesn't have that fix. Since nixpkgs' own ExecStart can't be
    # edited in place from here, mkForce replaces it with a wrapper that
    # merges the already-generated registration's tokens into our own
    # writable render of the identical settings attrset
    # (config.services.mautrix-telegram.settings — the same value nixpkgs'
    # own module renders, just written somewhere we can also touch) before
    # exec'ing the real binary. Token GENERATION itself (in preStart) is
    # untouched and already works; only the "get it into the running
    # process's config" step was broken. Confirmed fixed via a real VM
    # test: telegram stayed running continuously once started, no more
    # crash-loop, after this wrapper was introduced.
    systemd.services.mautrix-telegram = mkIf cfg.bridge.telegram.enable {
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "mautrix-telegram";
        Group = "mautrix-telegram";
        ExecStart =
          let
            ourSettings = (pkgs.formats.json { }).generate
              "mautrix-telegram-config-base.json"
              config.services.mautrix-telegram.settings;
            merged = "/var/lib/mautrix-telegram/config-with-tokens.json";
          in
          lib.mkForce "${pkgs.writeShellScript "mautrix-telegram-start" ''
            set -eu
            ${pkgs.yq}/bin/yq -s \
              '.[0].appservice.as_token = .[1].as_token
               | .[0].appservice.hs_token = .[1].hs_token
               | .[0]' \
              ${ourSettings} /var/lib/mautrix-telegram/telegram-registration.yaml \
              > ${merged}.tmp
            mv ${merged}.tmp ${merged}
            exec ${pkgs.mautrix-telegram}/bin/mautrix-telegram --config=${merged}
          ''}";
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 cfg.port cfg.clientPort ]
      ++ lib.optionals (cfg.bridge.whatsapp.enable) [ cfg.bridge.whatsapp.port ]
      ++ lib.optionals (cfg.bridge.signal.enable) [ cfg.bridge.signal.port ]
      ++ lib.optionals (cfg.bridge.telegram.enable) [ cfg.bridge.telegram.port ];

    networking.firewall.allowedUDPPortRanges = lib.optionals cfg.turn.enable (
      let parts = lib.splitString "-" cfg.turn.portRange;
      in [{ from = lib.toInt (builtins.elemAt parts 0); to = lib.toInt (builtins.elemAt parts 1); }]
    );

    # NB on first-boot ordering (found via an actual VM test with all three
    # bridges enabled, then reverted after breaking it further — see git
    # history): each bridge's registerToSynapse points Synapse's
    # app_service_config_files at a registration file the bridge only
    # generates in its own preStart, so a fresh boot has Synapse crash once
    # (FileNotFoundError) before the bridge — started in parallel, since
    # nixpkgs' bridge modules default `after = [ matrix-synapse.service ]`
    # but that only waits for Synapse's *start job* to finish, not succeed —
    # gets a chance to write the file. Synapse's `Restart = "on-failure"`
    # then retries and comes up clean. Adding an explicit
    # matrix-synapse-after-bridge ordering here to "fix" that instead
    # creates a genuine dependency cycle with the bridges' own
    # after=matrix-synapse.service default (systemd resolves it by
    # silently dropping an edge, leaving Synapse permanently inactive) —
    # worse than the self-healing restart nixpkgs already relies on. Left
    # as-is; operators should expect one failed start on first boot.

    security.acme = mkIf cfg.enableTls {
      acceptTerms = true;
      defaults.email = cfg.adminEmail;
    };

    services.nginx = mkIf cfg.enableTls {
      enable = true;
      virtualHosts."${domain}" = {
        enableACME = true;
        forceSSL = true;
        locations."/".proxyPass = "http://127.0.0.1:${toString cfg.clientPort}";
        extraConfig = ''
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };

    services.matrix-synapse = mkIf (cfg.implementation == "synapse") {
      enable = true;
      settings = {
        server_name = domain;
        database.name = cfg.databaseType;
        listeners = [
          {
            port = cfg.clientPort;
            bind_addresses = [ "127.0.0.1" ];
            type = "http";
            tls = false;
            x_forwarded = cfg.enableTls;
            resources = [
              { names = [ "client" ]; compress = true; }
              { names = [ "federation" ]; compress = false; }
            ];
          }
          {
            port = cfg.port;
            bind_addresses = [ "0.0.0.0" ];
            type = "http";
            # Was hardcoded `tls = true` unconditionally, with no
            # tls_certificate_path/tls_private_key_path ever set — Synapse
            # refuses to start in that state ("tls_certificate_path must be
            # specified if TLS-enabled listeners are configured"), caught by
            # an actual VM boot. Federation terminates TLS directly here
            # (nginx above only proxies the client port), so it follows
            # cfg.enableTls and reuses the same ACME cert as the client vhost.
            tls = cfg.enableTls;
            x_forwarded = false;
            resources = [
              { names = [ "federation" ]; compress = false; }
            ];
          }
        ];
      } // lib.optionalAttrs cfg.enableTls {
        tls_certificate_path = "/var/lib/acme/${domain}/fullchain.pem";
        tls_private_key_path = "/var/lib/acme/${domain}/key.pem";
      } // {
        enable_registration = cfg.enableRegistration;
        registration_shared_secret = mkIf (cfg.registrationSharedSecret != "") cfg.registrationSharedSecret;
        # whatsapp/telegram/signal bridges each generate an appservice
        # registration file, but only mautrix-signal's module in this
        # nixpkgs revision (24.05, pinned Dec 2024) has the
        # registerToSynapse option that auto-adds it here — whatsapp and
        # telegram's modules don't have that option at all yet (confirmed
        # via direct eval: builtins.attrNames on each module's config,
        # not assumed — re-confirmed directly against the pinned nixpkgs
        # source after an earlier pass here briefly assumed otherwise
        # based on inspecting a different, newer nixpkgs channel by
        # mistake). Without this, those two bridges run but are
        # completely invisible to Synapse — every request from them 401s
        # with "Invalid access token", found via an actual VM test.
        # Signal's own module still does its own wiring; not duplicated
        # here.
        app_service_config_files =
          lib.optional cfg.bridge.whatsapp.enable "/var/lib/mautrix-whatsapp/whatsapp-registration.yaml"
          ++ lib.optional cfg.bridge.telegram.enable "/var/lib/mautrix-telegram/telegram-registration.yaml";
      } // cfg.extraConfig // (lib.optionalAttrs cfg.sso.enable {
        # NB: must be lib.optionalAttrs, not mkIf — this whole expression is
        # combined with `//` (plain attrset union) below, and `//` does not
        # unwrap mkIf; it would merge in mkIf's internal {_type;condition;
        # content;} representation as literal settings keys instead of
        # conditionally including oidc_providers.
        oidc_providers = [({
          idp_id = "sovereign";
          idp_name = "Sovereign Host SSO";
          issuer = cfg.sso.providerUrl;
          client_id = cfg.sso.clientId;
          skip_verification = cfg.sso.skipVerification;
          scopes = [ "openid" "profile" "email" ];
          user_mapping_provider = {
            config = {
              localpart_template = "{{ user.preferred_username }}";
              display_name_template = "{{ user.name }}";
              email_template = "{{ user.email }}";
            };
          };
        } // lib.optionalAttrs (cfg.sso.clientSecretFile != null) {
          # Synapse reads this file itself at runtime — never embedded in
          # the Nix-generated config (which otherwise lands world-readable
          # in /nix/store; confirmed against Synapse's own config/oidc.py
          # source, not assumed).
          client_secret_path = toString cfg.sso.clientSecretFile;
        })];
      }) // (lib.optionalAttrs cfg.turn.enable ({
        turn_uris = [ "turn:${domain}:3478?transport=udp" "turn:${domain}:3478?transport=tcp" ];
      } // lib.optionalAttrs (cfg.turn.sharedSecretFile != null) {
        # Same pattern as client_secret_path above (confirmed against
        # Synapse's config/voip.py source).
        turn_shared_secret_path = toString cfg.turn.sharedSecretFile;
      }));
    };

    services.dendrite = mkIf (cfg.implementation == "dendrite") {
      enable = true;
      settings = {
        global = {
          server_name = domain;
          jetstream.max_messages = "10000";
        };
      };
    };

    # Bridges
    services.mautrix-whatsapp = mkIf cfg.bridge.whatsapp.enable {
      enable = true;
      settings = {
        homeserver.address = "http://127.0.0.1:${toString cfg.clientPort}";
        homeserver.domain = domain;
        appservice.port = cfg.bridge.whatsapp.port;
        bridge.permissions."*" = "relay";
        bridge.permissions."@admin:${domain}" = "admin";
      };
    };

    services.mautrix-signal = mkIf cfg.bridge.signal.enable {
      enable = true;
      settings = {
        homeserver.address = "http://127.0.0.1:${toString cfg.clientPort}";
        homeserver.domain = domain;
        appservice.port = cfg.bridge.signal.port;
        # nixpkgs' own default is bridge.permissions."*" = "relay", which
        # cannot personally log in/pair an account (only relay). Without an
        # explicit admin grant here, nobody could ever use this bridge
        # beyond that — same gap already fixed for whatsapp below, found by
        # diffing this module against the whatsapp block.
        bridge.permissions."@admin:${domain}" = "admin";
      };
    };

    services.mautrix-telegram = mkIf cfg.bridge.telegram.enable {
      enable = true;
      environmentFile = cfg.bridge.telegram.environmentFile;
      settings = {
        homeserver.address = "http://127.0.0.1:${toString cfg.clientPort}";
        homeserver.domain = domain;
        appservice.port = cfg.bridge.telegram.port;
        bridge.permissions."@admin:${domain}" = "admin";
      } // lib.optionalAttrs (cfg.bridge.telegram.environmentFile != null) {
        # Placeholders substituted by the module's own preStart envsubst
        # step from environmentFile — never land in the Nix store as
        # plaintext. Without api_id/api_hash the bridge has no default and
        # cannot authenticate to Telegram at all (checked against nixpkgs'
        # mautrix-telegram module source: no fallback, no assertion —
        # it just fails at runtime).
        telegram.api_id = "\${TELEGRAM_API_ID}";
        telegram.api_hash = "\${TELEGRAM_API_HASH}";
      };
    };

    # TURN server for VoIP
    services.coturn = mkIf cfg.turn.enable {
      enable = true;
      realm = domain;
      no-cli = true;
      no-tls = false;
      no-dtls = false;
      use-auth-secret = true;
      # coturn's own module asserts static-auth-secret and
      # static-auth-secret-file can't both be set — mirror the null-vs-file
      # split, same secret file as Synapse's turn_shared_secret_path above.
      static-auth-secret = null;
      # coturn's own option is types.str, not types.path — a bare derivation/
      # path value fails its type check ("not of type null or string"),
      # found via an actual eval error while writing a real integration
      # test (the earlier manual eval check happened to pass a literal
      # string, masking this).
      static-auth-secret-file = lib.mapNullable toString cfg.turn.sharedSecretFile;
      cli-password = null;
      extraConfig = ''
        fingerprint
        no-multicast-peers
      '';
    };
  };
}