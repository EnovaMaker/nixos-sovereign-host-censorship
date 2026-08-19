# Backup test: actually trigger a real backup run against the fixture's
# repo/paths, and assert it exits cleanly — the unit merely being *defined*
# (as this test checked before) doesn't catch a repo-initialization or
# tmpfiles bug, both found by an actual run.
machine.succeed("which borg || which restic || echo BACKUP_ENGINE_ABSENT")
machine.succeed("systemctl list-unit-files sovereign-backup.service --no-legend | grep -q sovereign-backup")

machine.succeed("mkdir -p /var/test-data && echo test-content > /var/test-data/file.txt")

machine.succeed("systemctl start sovereign-backup.service")
result = machine.succeed(
    "systemctl show -p Result --value sovereign-backup.service"
).strip()
assert result == "success", f"sovereign-backup did not exit cleanly: Result={result}"

backup_log = machine.succeed("cat /var/cache/sovereign-backup/backup-*.log")
assert "Backup completed successfully" in backup_log or "[OK]" in backup_log, backup_log

# The borg repo must have been auto-initialized, not left for the operator
# to `borg init` by hand — this is what actually broke before the fix.
machine.succeed("borg info /var/test-backup")

res = machine.succeed("sovereign backup 2>&1 || echo CLI_ABSENT")
print(res)

print("=== Backup test done ===")
