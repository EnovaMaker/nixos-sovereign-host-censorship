{ lib, ... }:

{
  # Default Prometheus alert rules for common services
  defaultAlertRules = {
    groups = [{
      name = "sovereign-host";
      rules = [
        {
          alert = "ServiceDown";
          expr = "up == 0";
          for = "5m";
          labels.severity = "critical";
          annotations.summary = "Service {{ $labels.job }} is down";
        }
        {
          alert = "HighCpuUsage";
          expr = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 80";
          for = "10m";
          labels.severity = "warning";
          annotations.summary = "CPU usage above 80% on {{ $labels.instance }}";
        }
        {
          alert = "DiskSpaceLow";
          expr = "(node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100 < 10";
          for = "5m";
          labels.severity = "critical";
          annotations.summary = "Disk space below 10% on {{ $labels.instance }}";
        }
        {
          alert = "BackupFailed";
          expr = "time() - sovereign_backup_last_success > 86400";
          for = "0m";
          labels.severity = "critical";
          annotations.summary = "Backup has not succeeded in over 24 hours";
        }
      ];
    }];
  };

  # Default Grafana dashboards (provisioning JSON)
  defaultDashboards = {
    "node-exporter.json" = {
      title = "Node Exporter";
      tags = [ "sovereign-host" "node" ];
      schemaVersion = 36;
      panels = [];
    };
    "matrix.json" = {
      title = "Matrix";
      tags = [ "sovereign-host" "matrix" ];
      schemaVersion = 36;
      panels = [];
    };
    "syncthing.json" = {
      title = "Syncthing";
      tags = [ "sovereign-host" "syncthing" ];
      schemaVersion = 36;
      panels = [];
    };
  };
}
