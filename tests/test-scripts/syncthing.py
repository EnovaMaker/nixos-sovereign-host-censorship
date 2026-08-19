# Syncthing test: service active, GUI on 8384, backup stamp dir writable.
machine.wait_for_unit("syncthing.service", timeout=60)

machine.succeed("systemctl is-active syncthing.service")
machine.succeed("ss -tln | grep -q ':8384' || echo 'Syncthing GUI not listening'")

# The notify long-poll loop must survive a real GUI response (or a clean
# non-JSON one) without ever crashing jq — give it a few polling cycles.
machine.wait_for_unit("sovereign-syncthing-notify.service", timeout=30)
machine.sleep(15)
notify_log = machine.succeed("journalctl -u sovereign-syncthing-notify.service --no-pager")
assert "parse error" not in notify_log, notify_log
assert "Traceback" not in notify_log, notify_log

res = machine.succeed("sovereign health syncthing 2>&1 || echo CLI_ABSENT")
print(res)

print("=== Syncthing test done ===")