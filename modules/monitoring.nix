{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.services.sovereign.monitoring;
  domain = cfg.domain;
  inherit (import ../lib { inherit lib; }) defaultAlertRules defaultDashboards;
in
{
  options.services.sovereign.monitoring = {
    enable = mkEnableOption "Prometheus + Grafana + Alertmanager monitoring";

    domain = mkOption {
      type = types.str;
      default = "monitoring.localhost";
      description = "Domain for monitoring services";
    };

    adminEmail = mkOption {
      type = types.str;
      default = "admin@${domain}";
      description = "Admin email for TLS";
    };

    enableTls = mkOption {
      type = types.bool;
      default = true;
      description = "Enable TLS for monitoring UI";
    };

    retentionDays = mkOption {
      type = types.int;
      default = 30;
      description = "Prometheus data retention in days";
    };

    scrapeInterval = mkOption {
      type = types.str;
      default = "15s";
      description = "Prometheus scrape interval";
    };

    evaluationInterval = mkOption {
      type = types.str;
      default = "15s";
      description = "Prometheus rule evaluation interval";
    };

    extraScrapeTargets = mkOption {
      type = types.listOf (types.submodule {
        options = {
          jobName = mkOption { type = types.str; };
          staticConfigs = mkOption {
            type = types.listOf (types.submodule {
              options.targets = mkOption { type = types.listOf types.str; };
            });
            default = [];
          };
        };
      });
      default = [];
      description = "Additional Prometheus scrape targets";
    };

    alertRules = mkOption {
      type = types.attrsOf types.anything;
      default = defaultAlertRules;
      description = "Prometheus alerting rules";
    };

    alertmanager = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Alertmanager";
      };

      port = mkOption {
        type = types.port;
        default = 9093;
        description = "Alertmanager port";
      };

      matrixWebhook = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Matrix webhook URL for alert notifications";
      };

      email.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable email notifications";
      };

      email.smtpHost = mkOption {
        type = types.str;
        default = "localhost";
        description = "SMTP host";
      };

      email.from = mkOption {
        type = types.str;
        default = "alertmanager@${domain}";
        description = "Alertmanager from address";
      };
    };

    grafana = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Grafana dashboards";
      };

      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Grafana listening port";
      };

      adminUser = mkOption {
        type = types.str;
        default = "admin";
        description = "Grafana admin user";
      };

      adminPassword = mkOption {
        type = types.str;
        default = "";
        description = "Grafana admin password (auto-generated if empty)";
      };

      dashboards = mkOption {
        type = types.attrsOf types.anything;
        default = defaultDashboards;
        description = "Provisioned Grafana dashboards";
      };

      datasources = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption { type = types.str; };
            type = mkOption { type = types.enum [ "prometheus" "influxdb" "graphite" ]; default = "prometheus"; };
            url = mkOption { type = types.str; };
            access = mkOption { type = types.enum [ "proxy" "direct" ]; default = "proxy"; };
          };
        });
        default = [
          { name = "Prometheus"; type = "prometheus"; url = "http://127.0.0.1:9090"; }
        ];
        description = "Grafana datasources";
      };
    };

    nodeExporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable node exporter for host metrics";
      };

      port = mkOption {
        type = types.port;
        default = 9100;
        description = "Node exporter port";
      };
    };

    exporters = {
      matrix = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Matrix metrics exporter";
      };

      nginx = mkOption {
        type = types.bool;
        default = false;
        description = "Enable nginx metrics exporter. NOT YET WIRED — no exporter package, systemd service, or scrape config is created by this module for it yet (unlike exporters.matrix/node).";
      };

      postgres = mkOption {
        type = types.bool;
        default = false;
        description = "Enable PostgreSQL metrics exporter. NOT YET WIRED — no exporter package, systemd service, or scrape config is created by this module for it yet (unlike exporters.matrix/node).";
      };
    };
  };

  config = mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      port = 9090;
      retentionTime = "${toString cfg.retentionDays}d";
      scrapeConfigs = lib.optionals cfg.nodeExporter.enable [{
        job_name = "node";
        scrape_interval = cfg.scrapeInterval;
        static_configs = [{ targets = [ "127.0.0.1:${toString cfg.nodeExporter.port}" ]; }];
      }] ++ lib.optionals cfg.exporters.matrix [{
        job_name = "matrix";
        scrape_interval = cfg.scrapeInterval;
        static_configs = [{ targets = [ "127.0.0.1:9092" ]; }];
      }] ++ (map (t: {
        job_name = t.jobName;
        static_configs = map (sc: { targets = sc.targets; }) t.staticConfigs;
      }) cfg.extraScrapeTargets);

      ruleFiles = mkIf (cfg.alertRules != { }) [(pkgs.writeText "prom-rules.yaml" (builtins.toJSON cfg.alertRules))];
      globalConfig.evaluation_interval = cfg.evaluationInterval;
    };

    services.prometheus.alertmanager = mkIf cfg.alertmanager.enable {
      enable = true;
      port = cfg.alertmanager.port;
      configuration = {
        global = { resolve_timeout = "5m"; }
          // (lib.optionalAttrs cfg.alertmanager.email.enable {
            smtp_smarthost = cfg.alertmanager.email.smtpHost;
            smtp_from = cfg.alertmanager.email.from;
          });
        receivers = [{
          name = "default";
          webhook_configs = lib.optional (cfg.alertmanager.matrixWebhook != null) {
            url = cfg.alertmanager.matrixWebhook;
            send_resolved = true;
          };
          email_configs = lib.optional cfg.alertmanager.email.enable {
            to = cfg.adminEmail;
            send_resolved = true;
          };
        }];
        route = {
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "4h";
          receiver = "default";
        };
      };
    };

    environment.etc = mkIf cfg.grafana.enable (lib.mapAttrs' (name: dashboard: {
      name = "grafana/provisioning/dashboards/sovereign-host/${name}";
      value.text = builtins.toJSON dashboard;
    }) cfg.grafana.dashboards);

    services.grafana = mkIf cfg.grafana.enable {
      enable = true;
      settings = {
        server = {
          http_addr = "127.0.0.1";
          http_port = cfg.grafana.port;
          domain = domain;
          root_url = "https://${domain}";
        };
        security = {
          admin_user = cfg.grafana.adminUser;
          admin_password = mkIf (cfg.grafana.adminPassword != "") cfg.grafana.adminPassword;
        };
        auth.anonymous = false;
      };

      provision.datasources.settings.datasources = cfg.grafana.datasources;

        provision.dashboards.settings.providers = [{
          name = "sovereign-host";
          orgId = 1;
          folder = "Sovereign Host";
          type = "file";
          disableDeletion = false;
          updateIntervalSeconds = 10;
          options.path = "/etc/grafana/provisioning/dashboards/sovereign-host";
        }];
    };

    services.prometheus.exporters.node = mkIf cfg.nodeExporter.enable {
      enable = true;
      port = cfg.nodeExporter.port;
      enabledCollectors = [ "systemd" "textfile" ];
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
        locations."/".proxyPass = "http://127.0.0.1:${toString cfg.grafana.port}";
      };
    };

    networking.firewall.allowedTCPPorts = [ 80 443 ]
      ++ lib.optionals cfg.nodeExporter.enable [ cfg.nodeExporter.port ]
      ++ lib.optionals cfg.alertmanager.enable [ cfg.alertmanager.port ];
  };
}