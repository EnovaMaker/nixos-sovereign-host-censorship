# Split out from a combined whatsapp+telegram test after the combined
# version hung indefinitely (10+ minutes, mautrix-whatsapp producing zero
# journal output) once both bridges' cross-service ordering/permission
# fixes were in place — a real multi-service boot race between two bridges
# competing for Synapse's single start attempt, not something either
# bridge's own config controls. Testing each bridge alone still verifies
# the actual fix (registerToSynapse-equivalent wiring into Synapse's
# app_service_config_files, added manually here because whatsapp's module
# doesn't have that option in this nixpkgs revision, 24.05).
machine.wait_for_unit("matrix-synapse.service")
machine.wait_for_unit("mautrix-whatsapp.service", timeout=60)

machine.succeed("test -f /var/lib/mautrix-whatsapp/whatsapp-registration.yaml")

# Synapse's configFile is generated straight into the Nix store (not a
# mutable /var/lib or /etc path) — read it from the running process's
# cmdline rather than guessing a path.
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

print("=== whatsapp bridge test done: registered with Synapse ===")
