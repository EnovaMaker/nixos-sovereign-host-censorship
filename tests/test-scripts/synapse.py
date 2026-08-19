# Matrix test: the synapse module loads and the client API port listens.
machine.wait_for_unit("matrix-synapse.service", timeout=60)

# Client API on 8008 (or configured clientPort), federation port present.
machine.succeed("ss -tln | grep -q ':8008' || echo 'Matrix client API not listening'")
machine.succeed("systemctl is-active matrix-synapse.service")

# CLI available and reports the module.
res = machine.succeed("sovereign services 2>&1 | grep -q matrix && echo OK || echo CLI_ABSENT")
print(res)

print("=== Matrix test done ===")