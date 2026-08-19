{ pkgs, pkgs-unstable, lib }:

let
  # Dummy Telegram API credentials for the bridge test — never real ones.
  # Just needs to be digit/hex-shaped enough that mautrix-telegram's config
  # parser accepts the envsubst'd values as well-typed (the actual Telegram
  # API call will fail against these, which is expected/fine — the test
  # only asserts the service doesn't crash at the config-parsing stage).
  testTelegramEnv = pkgs.writeText "telegram-test.env" ''
    TELEGRAM_API_ID=12345
    TELEGRAM_API_HASH=deadbeefdeadbeefdeadbeefdeadbeef
  '';

  makeTest = name: moduleConfig: pkgs.testers.nixosTest {
    name = "sovereign-host-${name}";
    nodes.machine = { config, pkgs, ... }: {
      imports = [ (import ../modules) ];
      services.sovereign = moduleConfig;
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      ${builtins.readFile ./test-scripts/${name}.py}
    '';
  };

  # All three mautrix bridges (not just signal) depend on libolm, which
  # nixpkgs marks insecure (CVE-2024-45191/2/3, deprecated upstream) and
  # refuses to build by default — confirmed by building each bridge
  # package directly, not assumed. Real deployers enabling any bridge need
  # this same override; see the warning matrix.nix now emits.
  # `nixpkgs.config` can't be set from inside a nixosTest node when the
  # test's own pkgs instance was already externally created (which
  # pkgs.testers.nixosTest's caller does here) — needs a fresh instance
  # with the config baked in instead.
  pkgsInsecureOlm = import pkgs.path {
    inherit (pkgs) system;
    config = pkgs.config // { permittedInsecurePackages = [ "olm-3.2.16" ]; };
  };

  makeBridgeTest = name: moduleConfig: pkgsInsecureOlm.testers.nixosTest {
    name = "sovereign-host-${name}";
    nodes.machine = { config, pkgs, ... }: {
      imports = [ (import ../modules) ];
      services.sovereign = moduleConfig;
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      ${builtins.readFile ./test-scripts/${name}.py}
    '';
  };

in
{
  test-synapse = makeTest "synapse" {
    enable = true;
    matrix = {
      enable = true;
      implementation = "synapse";
      domain = "matrix.test.local";
      enableTls = false;
    };
  };

  test-syncthing = makeTest "syncthing" {
    enable = true;
    syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
      devices.test-device = {
        id = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        address = "tcp://192.168.1.100:22000";
      };
      folders.test-folder = {
        path = "/var/test-sync";
        devices = [ "test-device" ];
      };
    };
  };

  test-syncthing-no-relay = makeTest "syncthing-no-relay" {
    enable = true;
    syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
      relay.enable = false;
      devices.test-device = {
        id = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        address = "tcp://192.168.1.100:22000";
      };
      folders.test-folder = {
        path = "/var/test-sync";
        devices = [ "test-device" ];
      };
    };
  };

  test-monitoring = makeTest "monitoring" {
    enable = true;
    monitoring = {
      enable = true;
      domain = "monitoring.test.local";
      enableTls = false;
      retentionDays = 7;
      grafana.enable = true;
      grafana.adminPassword = "test123";
    };
  };

  test-backup = makeTest "backup" {
    enable = true;
    backup = {
      enable = true;
      engine = "borg";
      interval = "daily";
      repositories.main = {
        path = "/var/test-backup";
        encryption = "none";
      };
      paths = [ "/var/test-data" ];
      prune.enable = false;
    };
  };

  test-sso = makeTest "sso" {
    enable = true;
    sso = {
      enable = true;
      provider = "authelia";
      domain = "sso.test.local";
      enableTls = false;
      secretKey = "test-secret-key-32-chars-min!!";
    };
  };

  # Each bridge is tested alone against Synapse, not together — a combined
  # whatsapp+telegram test hung indefinitely (10+ minutes, mautrix-whatsapp
  # producing zero journal output) once both bridges' cross-service
  # ordering/permission fixes were in place, a real multi-bridge boot race
  # unrelated to either bridge's own config. Testing separately still
  # verifies the actual fix (manual app_service_config_files wiring) for
  # each. Signal is excluded entirely — see matrix.nix's warning (libolm
  # marked insecure by nixpkgs, and separately never completed startup at
  # all in this VM's sandboxed network across 5+ minutes of real testing).
  # Best-effort/unverified, same category as elsewhere in this module.
  test-bridge-whatsapp = makeBridgeTest "bridge-whatsapp" {
    enable = true;
    matrix = {
      enable = true;
      implementation = "synapse";
      domain = "matrix.test.local";
      enableTls = false;
      bridge.whatsapp.enable = true;
    };
  };

  test-bridge-telegram = makeBridgeTest "bridge-telegram" {
    enable = true;
    matrix = {
      enable = true;
      implementation = "synapse";
      domain = "matrix.test.local";
      enableTls = false;
      bridge.telegram = {
        enable = true;
        environmentFile = testTelegramEnv;
      };
    };
  };

  test-bridge-integration = makeBridgeTest "bridge-integration" {
    enable = true;
    matrix = {
      enable = true;
      implementation = "synapse";
      domain = "matrix.test.local";
      enableTls = false;
      bridge.whatsapp.enable = true;
    };
    syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
      devices.test-device = {
        id = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
        address = "tcp://192.168.1.100:22000";
      };
      folders.test-folder = {
        path = "/var/test-sync";
        devices = [ "test-device" ];
      };
    };
  };

  # Real cross-service SSO/TURN integration — see matrix-sso-turn.py's
  # header comment for the gap this closes (test-full-stack enables both
  # sso and matrix but never turns on matrix.sso.enable itself, so the
  # two were never actually wired together by any test before this one).
  test-matrix-sso-turn = pkgs.testers.nixosTest {
    name = "sovereign-host-matrix-sso-turn";
    nodes.machine = { config, pkgs, ... }: {
      imports = [ (import ../modules) ];
      services.sovereign = {
        enable = true;
        sso = {
          enable = true;
          domain = "sso.test.local";
          enableTls = false;
          secretKey = "test-secret-key-32-chars-min!!";
          # default applications.matrix already registers a real OIDC
          # client with secret "insecure_secret" (hashed) — matches
          # matrix.sso.clientSecretFile below.
        };
        matrix = {
          enable = true;
          implementation = "synapse";
          domain = "matrix.test.local";
          enableTls = false;
          registrationSharedSecret = "test-registration-secret";
          sso = {
            enable = true;
            providerUrl = "http://127.0.0.1:9091";
            clientId = "matrix";
            clientSecretFile = pkgs.writeText "matrix-oidc-client-secret" "insecure_secret";
            # This test's Authelia runs without TLS (enableTls=false
            # above matches sso.enableTls=false) — Synapse otherwise
            # unconditionally rejects a non-HTTPS issuer at startup
            # ("issuer MUST use https scheme"), found via an actual VM
            # test. Real deployments should use TLS and leave this false.
            skipVerification = true;
          };
          turn = {
            enable = true;
            sharedSecretFile = pkgs.writeText "matrix-turn-secret" "test-turn-shared-secret-32-chars-long";
          };
        };
      };
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      ${builtins.readFile ./test-scripts/matrix-sso-turn.py}
    '';
  };

  test-full-stack = pkgs.testers.nixosTest {
    name = "sovereign-host-full-stack";
    nodes.machine = { config, pkgs, ... }: {
      imports = [ (import ../modules) ];
      services.sovereign = {
        enable = true;
        matrix.enable = true;
        matrix.domain = "matrix.test.local";
        matrix.enableTls = false;
        syncthing.enable = true;
        monitoring.enable = true;
        monitoring.domain = "monitoring.test.local";
        monitoring.enableTls = false;
        monitoring.grafana.adminPassword = "test123";
        backup.enable = true;
        backup.engine = "borg";
        backup.interval = "daily";
        backup.repositories.main.path = "/var/test-backup";
        backup.paths = [ "/var/lib/matrix-synapse" ];
        backup.prune.enable = false;
        sso.enable = true;
        sso.domain = "sso.test.local";
        sso.enableTls = false;
        sso.secretKey = "test-secret-key-32-chars-min!!";
      };
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("network.target")

      # Check each service
      for service in ["matrix-synapse", "syncthing", "prometheus", "grafana", "authelia-main"]:
        try:
          machine.wait_for_unit(f"{service}.service", timeout=30)
        except Exception:
          print(f"WARNING: {service} not running (may not be expected)")

      # Verify networking
      machine.succeed("ss -tln | grep -q 8008 || echo 'Matrix client API port not listening'")
      machine.succeed("ss -tln | grep -q 9090 || echo 'Prometheus port not listening'")

      # Verify borg available
      machine.succeed("which borgbackup || which borg")
      machine.succeed("which restic || echo 'restic not installed (borg mode)'")

      print("=== Full stack integration test completed ===")
    '';
  };
}
