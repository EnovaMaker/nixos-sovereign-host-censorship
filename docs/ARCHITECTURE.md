# Architecture — nixos-sovereign-host

## Overview

nixos-sovereign-host is a framework of composable NixOS modules. Each module
provides a `services.sovereign.<service>` interface. Services are designed to
work independently or together with zero-config integration.

**Funded vs. bonus scope:** the Restack grant
funds hardening Matrix + Syncthing specifically — the piece not already covered
by `ibizaman/selfhostblocks` (NLnet/NGI Zero-funded). Monitoring, backup and SSO
already exist below and ship as unfunded bonus modules.

## Module architecture

```
sovereign (services.sovereign.enable = true)
├── matrix     (services.sovereign.matrix.*)     — Synapse/Dendrite + bridges [funded]
├── syncthing  (services.sovereign.syncthing.*)  — P2P file sync [funded]
├── monitoring (services.sovereign.monitoring.*) — Prometheus + Grafana [bonus]
├── backup     (services.sovereign.backup.*)     — Borg/restic automation [bonus]
└── sso        (services.sovereign.sso.*)        — Authelia OIDC [bonus]
```

## Integration points

- **Monitoring → Matrix**: Alerts delivered via Matrix webhook
- **Backup → Matrix**: Success/failure notifications
- **SSO → Matrix**: OIDC authentication
- **SSO → Monitoring**: OIDC authentication
- **Monitoring → Services**: Prometheus auto-discovers enabled services
- **Backup → Services**: Pre-backup hooks stop services, post-backup restarts them

## Security

- File-based secrets compatible with sops-nix/agenix — bridge tokens and
  OIDC/TURN secrets are real `*_secret_path`/`*_secret_file` options
  (`client_secret_path`, `turn_shared_secret_path`,
  `static-auth-secret-file`), not placeholder values; credential rotation
  confirmed working (`preStart` re-reads the file on restart)
- TLS via ACME/Let's Encrypt by default
- OIDC (Authelia — the only OIDC provider currently packaged in nixpkgs 24.05)
  for user-facing services
- Backup encryption at rest and in transit

## Known bugs fixed during review

- `matrix.nix`/`monitoring.nix`: `mkIf` combined via `//` doesn't unwrap —
  SSO/TURN config for Matrix, and node-exporter targets for monitoring, were
  silently never reaching the underlying service config. Fixed with
  `lib.optionalAttrs`/`lib.optionals`.
- `backup.nix`: multi-repository backups shared one concatenated passphrase
  across all repos instead of one per repo. Fixed.
- `syncthing.nix`: notify unit used `http://` against a GUI configured for
  `useTLS = true`, and `Restart=on-failure` on a script that exits 0 after one
  pass (never restarted after the first run). Fixed.
