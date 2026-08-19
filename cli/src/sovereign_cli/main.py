"""nixos-sovereign-host CLI — status, health and management.

Commands:
  sovereign status            overview of the running stack (--json-out for JSON)
  sovereign services          list sovereign modules and the units they own
  sovereign health <name>     health of a specific module's units, e.g. "matrix"
  sovereign backup            last backup result
"""

from __future__ import annotations

import os
import sys

import click
from tabulate import tabulate

from .status_core import MODULE_UNITS, collect, format_units


@click.group()
def cli():
    """nixos-sovereign-host — declarative self-hosting stack."""


@cli.command()
@click.option("--json-out", is_flag=True, default=False, help="Output as JSON")
def status(json_out: bool):
    """Show the current status of all sovereign-host modules."""
    status = collect()
    if json_out:
        import json

        click.echo(json.dumps({
            "modules": status.modules,
            "units": [u.__dict__ for u in status.units],
            "listening": status.listening,
            "last_backup": status.last_backup,
        }, indent=2))
        return

    click.echo(tabulate(
        [(m, "enabled" if on else "disabled") for m, on in status.modules.items()],
        headers=["Module", "State"],
        tablefmt="simple",
    ))
    click.echo()
    rows = format_units(status)
    if rows:
        click.echo(tabulate(rows, headers=["Unit", "Module", "State", ""], tablefmt="simple"))
    click.echo()
    click.echo(f"Listening ports: {', '.join(status.listening) or 'none'}")
    click.echo(f"Last backup: {status.last_backup}")


@cli.command()
def services():
    """List DNS-style service groups managed by sovereign-host."""
    for module, units in MODULE_UNITS.items():
        click.echo(f"{module}: {', '.join(units)}")


@cli.command()
@click.argument("name")
def health(name: str):
    """Probe the health of a sovereign module by name (e.g. matrix)."""
    status = collect()
    units = MODULE_UNITS.get(name.lower())
    if not units:
        click.echo(f"Unknown module '{name}'. Known: {', '.join(MODULE_UNITS)}", err=True)
        sys.exit(1)
    for u in units:
        matches = [s for s in status.units if s.name == u]
        for s in matches:
            state = "OK" if s.ok else (f"disabled" if s.active == "disabled" else s.active)
            click.echo(f"{s.name}: {state}")


@cli.command("backup")
def backup():
    """Show the status of the sovereign-host backup service."""
    status = collect()
    click.echo(f"Last backup: {status.last_backup}")
    for u in status.units:
        if u.name == "sovereign-backup":
            click.echo(f"sovereign-backup.service: {u.active}/{u.sub_state}")


if __name__ == "__main__":
    prog = os.path.basename(sys.argv[0]) if sys.argv else "sovereign"
    cli(prog_name=prog)