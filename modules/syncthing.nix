{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.sovereign.syncthing;
  guiPort = lib.toInt (lib.last (lib.splitString ":" cfg.guiAddress));
in
{
  options.services.sovereign.syncthing = {
    enable = mkEnableOption "Syncthing file synchronization";

    guiAddress = mkOption {
      type = types.str;
      default = "127.0.0.1:8384";
      description = "GUI listening address";
    };

    guiUser = mkOption {
      type = types.str;
      default = "admin";
      description = "GUI admin user";
    };

    guiPassword = mkOption {
      type = types.str;
      default = "";
      description = "GUI admin password (leave empty for generated)";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/syncthing";
      description = "Syncthing data directory";
    };

    devices = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          id = mkOption {
            type = types.str;
            description = "Device ID";
          };
          address = mkOption {
            type = types.str;
            default = "dynamic";
            description = "Device address (dynamic, tcp://..., or relay://...)";
          };
          introducer = mkOption {
            type = types.bool;
            default = false;
            description = "Whether this device is an introducer";
          };
          compression = mkOption {
            type = types.enum [ "always" "never" "metadata" ];
            default = "metadata";
            description = "Compression mode";
          };
        };
      });
      default = {};
      description = "Syncthing devices to connect to";
    };

    folders = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Local folder path";
          };
          devices = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Devices to share this folder with";
          };
          type = mkOption {
            type = types.enum [ "sendreceive" "sendonly" "receiveonly" ];
            default = "sendreceive";
            description = "Folder type";
          };
          rescanInterval = mkOption {
            type = types.int;
            default = 60;
            description = "Rescan interval in seconds";
          };
          versioning = mkOption {
            type = types.nullOr (types.enum [ "trashcan" "simple" "staggered" "external" ]);
            default = null;
            description = "File versioning strategy";
          };
        };
      });
      default = {};
      description = "Folders to synchronize";
    };

    relay.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable relay server";
    };

    relay.port = mkOption {
      type = types.port;
      default = 22067;
      description = "Relay server port";
    };

    discovery.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable global discovery";
    };

    discovery.port = mkOption {
      type = types.port;
      default = 21027;
      description = "Discovery server port (UDP)";
    };

    listenPort = mkOption {
      type = types.port;
      default = 22000;
      description = "Sync protocol listening port (TCP/UDP)";
    };

    limits.maxDownloadSpeed = mkOption {
      type = types.int;
      default = 0;
      description = "Max download speed in KiB/s (0 = unlimited)";
    };

    limits.maxUploadSpeed = mkOption {
      type = types.int;
      default = 0;
      description = "Max upload speed in KiB/s (0 = unlimited)";
    };
  };

  config = mkIf cfg.enable {
    services.syncthing = {
      inherit (cfg) enable guiAddress dataDir;

      settings = {
        devices = lib.mapAttrs' (name: dev: {
          name = name;
          value = {
            id = dev.id;
            addresses = [ dev.address ];
            introducer = dev.introducer;
            compression = dev.compression;
          };
        }) cfg.devices;

        folders = lib.mapAttrs' (name: fld: {
          name = name;
          value = {
            path = fld.path;
            devices = fld.devices;
            type = fld.type;
            rescanIntervalS = fld.rescanInterval;
            versioning = if fld.versioning != null then {
              type = fld.versioning;
              params.keep = "5";
            } else null;
          };
        }) cfg.folders;

        options = {
          relaysEnabled = cfg.relay.enable;
          localAnnounceEnabled = true;
          maxRecvKbps = mkIf (cfg.limits.maxDownloadSpeed > 0) cfg.limits.maxDownloadSpeed;
          maxSendKbps = mkIf (cfg.limits.maxUploadSpeed > 0) cfg.limits.maxUploadSpeed;
          globalAnnounceEnabled = cfg.discovery.enable;
        };

        gui = {
          inherit (cfg) guiUser;
          theme = "default";
          useTLS = true;
        } // lib.optionalAttrs (cfg.guiPassword != "") {
          password = cfg.guiPassword;
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.listenPort guiPort ]
      ++ lib.optionals cfg.relay.enable [ cfg.relay.port ];

    networking.firewall.allowedUDPPorts = [ cfg.discovery.port cfg.listenPort ];

    systemd.services.sovereign-syncthing-notify = {
      description = "Syncthing event notifications";
      wantedBy = [ "multi-user.target" ];
      # `wants`, not `bindsTo`: this unit should keep trying to reconnect on
      # its own rather than being stopped every time syncthing.service
      # restarts (bindsTo cascades stop/restart from the target).
      after = [ "syncthing.service" ];
      wants = [ "syncthing.service" ];
      serviceConfig = {
        # The GUI listener above always sets useTLS = true, so this must
        # talk https (with -k for the self-signed cert) — a plain http://
        # request against a TLS-only listener fails immediately.
        # Known limitation: long-polls with an incrementing `since` cursor so it
        # only logs genuinely new events instead of either replaying all
        # history each run or (per the old bindsTo+on-failure combo) going
        # silent forever after the first clean exit. No auth is sent —
        # relies on the GUI having no credentials configured (the default
        # here, since guiPassword defaults to ""); add curl -u/API-key
        # support if guiPassword is ever set.
        ExecStart = "${pkgs.writeShellScript "syncthing-notify" ''
          set -u
          since=0
          while true; do
            # --fail: on a non-2xx response (auth required, GUI not ready
            # yet, CSRF rejection) curl emits nothing and exits non-zero,
            # so $resp is empty and falls into the sleep branch below —
            # instead of a non-JSON error body reaching jq and crashing it.
            resp=$(${pkgs.curl}/bin/curl -sk --fail "https://${cfg.guiAddress}/rest/events?since=''${since}&timeout=30" || true)
            if [ -n "$resp" ] && [ "$resp" != "null" ] && echo "$resp" | ${pkgs.jq}/bin/jq empty 2>/dev/null; then
              echo "$resp" | ${pkgs.jq}/bin/jq --unbuffered -c '.[] | select(.type == "StateChanged" and .data.to == "syncing")' \
                | while read -r event; do
                  folder=$(echo "$event" | ${pkgs.jq}/bin/jq -r '.data.folder')
                  logger -t syncthing "Folder $folder is syncing"
                done
              last=$(echo "$resp" | ${pkgs.jq}/bin/jq -r '(.[-1].id // empty)')
              [ -n "$last" ] && since="$last"
            else
              sleep 5
            fi
          done
        ''}";
        Restart = "always";
        RestartSec = "30s";
        User = "syncthing";
      };
    };
  };
}