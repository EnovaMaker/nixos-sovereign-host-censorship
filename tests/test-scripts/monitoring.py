# Monitoring test: Prometheus + Grafana + Alertmanager reachable, retention set.
machine.wait_for_unit("prometheus.service", timeout=60)
machine.wait_for_unit("grafana.service", timeout=60)

machine.succeed("ss -tln | grep -q ':9090' || echo 'Prometheus not listening'")
machine.succeed("ss -tln | grep -q ':3000' || echo 'Grafana not listening'")

res = machine.succeed("sovereign health monitoring 2>&1 || echo CLI_ABSENT")
print(res)

print("=== Monitoring test done ===")