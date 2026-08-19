# Cross-service integration test (Matrix + bridge + Syncthing). Confirmed
# passing in a real VM run. Uses whatsapp only, not all three
# bridges together — a combined whatsapp+telegram test hit a real
# multi-bridge boot race (see tests/default.nix's comment on
# test-bridge-whatsapp/test-bridge-telegram), tested separately instead.
# Proves the load-bearing claim — that Matrix+bridge and Syncthing coexist
# on one host without interfering — without re-fighting that unrelated
# multi-bridge race.
machine.wait_for_unit("matrix-synapse.service")
machine.wait_for_unit("mautrix-whatsapp.service", timeout=60)
machine.wait_for_unit("syncthing.service", timeout=60)

machine.succeed("test -f /var/lib/mautrix-whatsapp/whatsapp-registration.yaml")

synapse_cmdline = machine.succeed(
    "tr '\\0' ' ' < /proc/$(systemctl show -p MainPID --value matrix-synapse.service)/cmdline"
)
synapse_config_path = [
    part for part in synapse_cmdline.split() if part.endswith("homeserver.yaml")
][0]
synapse_config = machine.succeed(f"cat {synapse_config_path}")
assert "mautrix-whatsapp" in synapse_config, (
    "mautrix-whatsapp's registration file not wired into Synapse's "
    "app_service_config_files — bridge would be running but invisible "
    "to the homeserver"
)

# Both services' network ports must be up simultaneously — the actual
# point of a cross-service test: neither one's port allocation, firewall
# rule, or startup ordering breaks the other.
machine.succeed("ss -tln | grep -q ':8008 '")   # Matrix client API
machine.succeed("ss -tln | grep -q ':8384 '")   # Syncthing GUI

print("=== bridge integration test done: matrix+whatsapp+syncthing coexist ===")
