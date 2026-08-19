{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.sovereign.backup;
in
{
  options.services.sovereign.backup = {
    enable = mkEnableOption "Automated backup system (Borg + restic)";

    engine = mkOption {
      type = types.enum [ "borg" "restic" ];
      default = "borg";
      description = "Backup engine";
    };

    interval = mkOption {
      type = types.str;
      default = "daily";
      description = "Backup schedule interval (systemd calendar expression)";
    };

    repositories = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          path = mkOption {
            type = types.str;
            description = "Repository path";
          };
          encryption = mkOption {
            type = types.enum [ "none" "repokey" "keyfile" ];
            default = "repokey";
            description = "Encryption mode";
          };
          passphrase = mkOption {
            type = types.str;
            default = "";
            description = "Repository passphrase (use sops-nix/agenix)";
          };
          compression = mkOption {
            type = types.enum [ "none" "lz4" "zstd" "lzma" ];
            default = "zstd";
            description = "Compression algorithm";
          };
        };
      });
      default = {};
      description = "Backup repositories";
    };

    paths = mkOption {
      type = types.listOf types.str;
      default = [
        "/var/lib/matrix-synapse"
        "/var/lib/syncthing"
        "/var/lib/grafana"
        "/var/lib/prometheus2"
      ];
      description = "Paths to back up";
    };

    preHooks = mkOption {
      type = types.listOf (types.submodule {
        options = {
          command = mkOption { type = types.str; };
          service = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Service to stop before running hook";
          };
        };
      });
      default = [];
      description = "Commands to run before backup (e.g., database dumps)";
    };

    postHooks = mkOption {
      type = types.listOf (types.submodule {
        options = {
          command = mkOption { type = types.str; };
          service = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Service to restart after running hook";
          };
        };
      });
      default = [];
      description = "Commands to run after backup (e.g., service restart)";
    };

    prune.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic pruning of old backups";
    };

    prune.policy = mkOption {
      type = types.submodule {
        options = {
          keepDaily = mkOption { type = types.int; default = 7; };
          keepWeekly = mkOption { type = types.int; default = 4; };
          keepMonthly = mkOption { type = types.int; default = 6; };
          keepYearly = mkOption { type = types.int; default = 2; };
        };
      };
      default = {};
      description = "Pruning policy";
    };

    notification.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable notifications on backup completion/failure";
    };

    notification.matrixWebhook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Matrix webhook URL for backup notifications";
    };

    healthchecks.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable healthchecks.io ping integration";
    };

    healthchecks.url = mkOption {
      type = types.str;
      default = "";
      description = "Healthchecks.io ping URL";
    };

    tmpDir = mkOption {
      type = types.str;
      default = "/var/cache/sovereign-backup";
      description = "Temporary directory for backup operations";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [ borgbackup restic ];

    systemd.tmpfiles.settings."sovereign-backup" = {
      "${cfg.tmpDir}" = {
        d = {
          mode = "0700";
          user = "root";
          group = "root";
        };
      };
    } // (lib.listToAttrs (map (path: {
      # builtins.dirOf, not string-concatenating "/..": systemd-tmpfiles
      # rejects any path containing a literal ".." component outright
      # ("path not normalized"), even when it would resolve to something
      # valid — caught by an actual boot, not eval (this line evaluates
      # fine, tmpfiles just refuses it at runtime).
      name = "${builtins.dirOf path}/.sovereign-backup-stamp";
      value = {
        f = {
          mode = "0644";
          user = "root";
          group = "root";
        };
      };
    }) cfg.paths));

    systemd.services.sovereign-backup = {
      description = "Sovereign Host automated backup";
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ borgbackup restic coreutils gnugrep gnutar gzip openssh ];

      script = ''
        set -euo pipefail

        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        LOGFILE="${cfg.tmpDir}/backup-''${TIMESTAMP}.log"
        STATUS=0

        notify() {
          local level="$1"
          local message="$2"
          echo "[''${level}] ''${message}" >> "''${LOGFILE}"

          ${lib.optionalString (cfg.notification.enable && cfg.notification.matrixWebhook != null) ''
            if [ -n "${cfg.notification.matrixWebhook}" ]; then
              ${pkgs.curl}/bin/curl -s -X POST \
                -H "Content-Type: application/json" \
                -d "{\"msgtype\":\"m.text\",\"body\":\"[Backup ''${level}] ''${message}\"}" \
                "${cfg.notification.matrixWebhook}" || true
            fi
          ''}
        }

        # Pre-hooks: stop services and dump databases
        ${lib.concatMapStringsSep "\n" (h: ''
          ${lib.optionalString (h.service != null) ''
            echo "Stopping ${h.service} before pre-hook" >> "''${LOGFILE}"
            systemctl stop '${h.service}' >> "''${LOGFILE}" 2>&1 || true
          ''}
          echo "Running pre-hook: ${h.command}" >> "''${LOGFILE}"
          eval '${h.command}' >> "''${LOGFILE}" 2>&1 || true
        '') cfg.preHooks}

        # Run backup based on engine. Each repository is handled in its own
        # block so its own passphrase/compression/prune settings are used —
        # do not flatten these across repositories (they used to be joined
        # into one space-separated string and applied to every repo, which
        # broke multi-repository configurations).
        ${lib.concatMapStringsSep "\n" (repo: ''
          BORG_REPO='${repo.path}'
          RESTIC_REPOSITORY='${repo.path}'
          export BORG_REPO RESTIC_REPOSITORY
          export BORG_PASSPHRASE='${repo.passphrase}'
          export RESTIC_PASSWORD='${repo.passphrase}'

          if [ "${cfg.engine}" = "borg" ]; then
            # Idempotent repo init: a fresh deployment's repo path is empty,
            # and `borg create` against an uninitialized repo fails outright
            # (caught by an actual VM run — the service crash-looped on the
            # very first backup with no repo ever initialized). `borg info`
            # exits non-zero only when the repo doesn't exist/isn't a repo.
            if ! ${pkgs.borgbackup}/bin/borg info "''${BORG_REPO}" >> "''${LOGFILE}" 2>&1; then
              ${pkgs.borgbackup}/bin/borg init --encryption=${repo.encryption} "''${BORG_REPO}" \
                >> "''${LOGFILE}" 2>&1 || STATUS=$?
            fi
            ${pkgs.borgbackup}/bin/borg create \
              --verbose --progress --stats \
              --compression '${repo.compression}' \
              "''${BORG_REPO}::sovereign-''${TIMESTAMP}" \
              ${builtins.toString (map (p: "'${p}'") cfg.paths)} \
              >> "''${LOGFILE}" 2>&1 || STATUS=$?
          else
            ${pkgs.restic}/bin/restic backup \
              --verbose \
              ${builtins.toString (map (p: "'${p}'") cfg.paths)} \
              >> "''${LOGFILE}" 2>&1 || STATUS=$?
          fi

          # Prune old backups (borg only; restic pruning needs `forget`
          # policy flags this module does not expose yet)
          if [ "${lib.boolToString cfg.prune.enable}" = "true" ] && [ "''${STATUS}" = "0" ] && [ "${cfg.engine}" = "borg" ]; then
            ${pkgs.borgbackup}/bin/borg prune \
              --keep-daily ${toString cfg.prune.policy.keepDaily} \
              --keep-weekly ${toString cfg.prune.policy.keepWeekly} \
              --keep-monthly ${toString cfg.prune.policy.keepMonthly} \
              --keep-yearly ${toString cfg.prune.policy.keepYearly} \
              "''${BORG_REPO}" \
              >> "''${LOGFILE}" 2>&1 || true
          fi
        '') (builtins.attrValues cfg.repositories)}

        # Post-hooks: restart services
        ${lib.concatMapStringsSep "\n" (h: ''
          echo "Running post-hook: ${h.command}" >> "''${LOGFILE}"
          eval '${h.command}' >> "''${LOGFILE}" 2>&1 || true
          ${lib.optionalString (h.service != null) ''
            echo "Restarting ${h.service} after post-hook" >> "''${LOGFILE}"
            systemctl start '${h.service}' >> "''${LOGFILE}" 2>&1 || true
          ''}
        '') cfg.postHooks}

        # Healthchecks ping
        if [ "${lib.boolToString cfg.healthchecks.enable}" = "true" ] && [ -n "${cfg.healthchecks.url}" ]; then
          if [ "''${STATUS}" = "0" ]; then
            ${pkgs.curl}/bin/curl -s "''${cfg.healthchecks.url}" || true
          else
            ${pkgs.curl}/bin/curl -s "''${cfg.healthchecks.url}/fail" || true
          fi
        fi

        # Notify result
        if [ "''${STATUS}" = "0" ]; then
          notify "OK" "Backup completed successfully"
        else
          notify "FAIL" "Backup failed with status ''${STATUS}. Check ''${LOGFILE}"
        fi

        exit ''${STATUS}
      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        StateDirectory = "sovereign-backup";
        ReadWritePaths = cfg.paths ++ [ cfg.tmpDir ];
        NoNewPrivileges = true;
        ProtectSystem = "full";
        PrivateTmp = true;
      };
    };

    systemd.timers.sovereign-backup = {
      description = "Scheduled sovereign-host backup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
    };
  };
}