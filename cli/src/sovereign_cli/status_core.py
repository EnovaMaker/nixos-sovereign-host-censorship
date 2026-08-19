"""Core service-status logic for nixos-sovereign-host.

Queries the local system via systemctl to build an honest, dependency-free
picture of the sovereign-host stack: which modules are enabled, which
systemd services are running, last backup result, and open listening ports.

The implementation only uses the Python stdlib (subprocess), so it runs
unchanged on any NixOS machine and inside the NixOS VM test harness.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field


@dataclass
class ServiceStatus:
    """A single systemd unit's runtime status."""

    name: str
    module: str
    active: str = "unknown"
    sub_state: str = ""

    @property
    def ok(self) -> bool:
        return self.active == "active" and self.sub_state in ("running", "active", "exited")


@dataclass
class HostStatus:
    """Aggregated view of the sovereign-host stack on this machine."""

    modules: dict[str, bool] = field(default_factory=dict)
    units: list[ServiceStatus] = field(default_factory=list)
    listening: list[str] = field(default_factory=list)
    last_backup: str = "unknown"
    errors: list[str] = field(default_factory=list)


# Mapping from sovereign module -> systemd units the CLI should report on.
# Kept intentionally short: unit names follow the services.* namespace used
# by nixpkgs. When a unit does not exist the CLI reports it as not-enabled.
MODULE_UNITS = {
    "matrix": ["matrix-synapse", "dendrite"],
    "syncthing": ["syncthing"],
    "monitoring": ["prometheus", "grafana", "prometheus-alertmanager"],
    "backup": ["sovereign-backup"],
    # modules/sso.nix only wires up services.authelia.instances.main, which
    # creates a unit named "authelia-main" — not "authelia" and not
    # "authentik-server" (Authentik isn't implemented, see sso.nix).
    "sso": ["authelia-main"],
}

# Modules with a one-shot unit that produces a stateful result.
ONESHOT_UNITS = ["sovereign-backup"]


def _run(cmd: list[str]) -> str:
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=15,
        )
        return proc.stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def is_active(unit: str) -> bool:
    return "active" in _run(["systemctl", "is-active", unit]).strip()


def unit_state(unit: str) -> ServiceStatus:
    parts = _run(["systemctl", "show", unit, "--property=ActiveState,SubState"]).strip().splitlines()
    fields = {"ActiveState": "unknown", "SubState": ""}
    for line in parts:
        if "=" in line:
            key, _, value = line.partition("=")
            fields[key] = value
    module = next((m for m, us in MODULE_UNITS.items() if unit in us), "core")
    return ServiceStatus(unit, module, fields["ActiveState"], fields["SubState"])


def _unit_exists(unit: str) -> bool:
    out = _run(["systemctl", "list-unit-files", unit, "--no-legend"]).strip()
    return unit in out


def listening_ports() -> list[str]:
    out = _run(["ss", "-tlnH"])
    ports = set()
    for line in out.splitlines():
        m = re.search(r":(\d{2,5})\s", line)
        if m:
            ports.add(m.group(1))
    return sorted(ports)


def last_backup_status() -> str:
    """Return the most recent sovereign-backup timer/service timestamp or log."""
    for unit in ("sovereign-backup.timer", "sovereign-backup.service"):
        out = _run(["systemctl", "show", unit, "--property=LastTriggerUSec,Result"])
        if out.strip():
            last = next((l.partition("=")[2] for l in out.splitlines() if "LastTriggerUSec=" in l), "")
            result = next((l.partition("=")[2] for l in out.splitlines() if "Result=" in l), "")
            if last:
                marker = f" (last: {last}, result: {result or 'pending'})"
                return marker
    return "never run"


def collect() -> HostStatus:
    """Collect the current stack status. Never raises on missing tools."""
    status = HostStatus()

    for module, units in MODULE_UNITS.items():
        enabled = any(_unit_exists(u) and is_active(u) for u in units)
        status.modules[module] = enabled
        for u in units:
            if _unit_exists(u):
                status.units.append(unit_state(u))
            else:
                status.units.append(ServiceStatus(u, module, "disabled", ""))

    status.listening = listening_ports()
    status.last_backup = last_backup_status()

    return status


def format_units(status: HostStatus) -> list[tuple[str, str, str, str]]:
    rows = []
    for u in status.units:
        state = "ok" if u.ok else ("disabled" if u.active == "disabled" else f"{u.active}/{u.sub_state}")
        rows.append((u.name, u.module, state, ""))
    return rows