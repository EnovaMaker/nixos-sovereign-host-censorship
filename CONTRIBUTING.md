# Contributing

## How to contribute

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `nix flake check` to validate
5. Submit a PR

## Code style

- Follow NixOS module conventions from nixpkgs
- Use `mkOption` with `type`, `description`, `default`
- All options must have sensible defaults
- Use `lib.mkEnableOption` for boolean toggles
- Document integration points with other modules

## Testing

- Tests use NixOS VM test infrastructure
- Run all: `nix flake check`
- Run single: `nix build .#checks.x86_64-linux.test-synapse`
- Each module has independent tests
- `test-full-stack` validates cross-module integration
