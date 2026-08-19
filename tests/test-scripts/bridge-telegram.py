# Split out from a combined whatsapp+telegram test — see bridge-whatsapp.py's
# header comment for why. Confirms telegram's registration file is wired
# into Synapse's app_service_config_files (added manually in matrix.nix,
# since telegram's module doesn't have registerToSynapse in this nixpkgs
# revision) and that the envsubst'd api_id/api_hash placeholders produce a
# config the bridge process can at least parse — not a Python type error
# from api_id landing as a JSON string — before it ever needs real network
# access to Telegram's API.
#
# Verification status: confirmed passing in a real VM run.
# Getting there surfaced two real bugs (not the earlier suspected resource
# contention): (1) DynamicUser made the bridge's state directory
# unreachable to Synapse by systemd design, fixed with a static user/group
# (same pattern as whatsapp); (2) the module wrote its generated
# appservice token back into a read-only Nix store path, fixed with a
# wrapper that merges it into a writable config copy. See
# docs/FINAL_REPORT.md for detail.
machine.wait_for_unit("matrix-synapse.service")
machine.wait_for_unit("mautrix-telegram.service", timeout=60)

machine.succeed("test -f /var/lib/mautrix-telegram/telegram-registration.yaml")

synapse_cmdline = machine.succeed(
    "tr '\\0' ' ' < /proc/$(systemctl show -p MainPID --value matrix-synapse.service)/cmdline"
)
synapse_config_path = [
    part for part in synapse_cmdline.split() if part.endswith("homeserver.yaml")
][0]
synapse_config = machine.succeed(f"cat {synapse_config_path}")
assert "mautrix-telegram" in synapse_config, (
    "mautrix-telegram's registration file not wired into Synapse's "
    "app_service_config_files — bridge would be running but invisible "
    "to the homeserver"
)

telegram_active = machine.succeed(
    "systemctl show -p ActiveState --value mautrix-telegram.service"
).strip()
assert telegram_active in ("active", "activating"), (
    f"mautrix-telegram not active/activating (ActiveState={telegram_active}) "
    f"— likely crashed parsing the envsubst'd api_id/api_hash config"
)

print("=== telegram bridge test done: registered with Synapse, config parses ===")
