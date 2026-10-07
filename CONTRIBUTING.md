# Contributing

## What this tree is

A **design preview**. It ships no modules, CLI or tests — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
for the design and [`docs/ROADMAP.md`](docs/ROADMAP.md) for what is planned and in what order.

So the most useful contribution right now is not code. It is telling us where the design is
wrong, before it is built:

- an operator's account of what actually breaks when a domain gets blocked
- a reason one of the milestones will not work as described
- prior art we missed — if something here already exists, we would rather know now
- a security assumption that does not hold

Open an issue. Design criticism at this stage is worth more than a patch.

## When there is code

Once modules land here, the
conventions are the ones this series follows throughout:

- NixOS module conventions from nixpkgs
- `mkOption` with `type` and `description`; `lib.mkEnableOption` for boolean toggles
- sensible defaults, and integration points with other modules documented
- NixOS VM tests, run with `nix flake check`

## Licence

Contributions are accepted under the [MIT licence](LICENSE) this project uses.
