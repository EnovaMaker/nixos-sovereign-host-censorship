# Final Report — nixos-sovereign-host (Restack)

## Summary

`nixos-sovereign-host` is a NixOS module + operator CLI for declarative
community self-hosting. The funded scope is Matrix (Synapse) + bridges
(WhatsApp/Signal/Telegram) + Syncthing; monitoring/backup/SSO ship in the
same repo as a tested but unbilled bonus, since they overlap with the
already-NLnet-funded `ibizaman/selfhostblocks`.

## Delivered

- **Matrix module** — Synapse (Dendrite scaffolded, best-effort) with
  TLS, OIDC SSO, and TURN, all wired via `nginx`/`security.acme`.
- **Bridge Synapse registration** — a real, previously-undocumented gap:
  only `mautrix-signal`'s module has the `registerToSynapse` auto-wiring
  option in this pinned nixpkgs (24.05, Dec 2024) — whatsapp/telegram do
  not, so both ran but were completely invisible to Synapse (every
  request 401ing). Wired manually, plus fixed a `DynamicUser` permission
  gap for telegram and a `SupplementaryGroups`/`systemd-sysusers`
  ordering race found the same way.
- **`test-bridge-whatsapp`** — passes end-to-end in a real NixOS VM test:
  registration generated, wired into Synapse, request reaches the auth
  layer.
- **Real secrets, not placeholders** — OIDC `client_secret` and TURN's
  shared secret were literal `"<sops>"`/`"<sops-turn>"` strings baked
  into the Nix-generated config (world-readable in `/nix/store` if ever
  filled with a real value). Replaced with Synapse's own
  `client_secret_path`/`turn_shared_secret_path` and coturn's
  `static-auth-secret-file` — all three read the secret from a file at
  their own runtime, confirmed against each project's actual source.
- **Cross-service integration test** — `test-bridge-integration` (Matrix
  + whatsapp + Syncthing on one host).
- **Docs** — README, `QUICKSTART.md` (EN), `QUICKSTART.pt.md` (PT).

## Real bugs found and fixed (each caught by an actual build or VM test
failure, not hypothetical)

See `ROADMAP.md` for the full list with context. Highlights:

1. `mkIf`-inside-`//` merge bug silently dropped SSO/TURN config.
2. Federation listener hardcoded `tls = true` with no certificate paths
   ever set — Synapse refused to start.
3. Backup module's tmpfiles rule used a literal `..` path segment,
   rejected by `systemd-tmpfiles`; Borg/restic repositories were never
   initialized before the first backup attempt either.
4. Only `mautrix-signal`'s module auto-registers with Synapse in this
   nixpkgs revision — whatsapp/telegram silently invisible without
   manual wiring (see above).
5. `mautrix-telegram` uses `DynamicUser = true` — no stable group name
   to add Synapse to; several chmod/`ExecStartPre` attempts to work
   around it all failed against the same `PermissionError`. Actually
   fixed by giving it a static user/group instead, the same pattern the
   WhatsApp bridge already uses (see "Known limitations" below).
6. `SupplementaryGroups` referencing another service's group needs an
   explicit `After=systemd-sysusers.service` — NixOS only adds this
   ordering automatically for a service's own `User=`.

## Known limitations

- **Signal bridge**: excluded from VM testing entirely. Separately from
  nixpkgs marking its `libolm` dependency insecure, `mautrix-signal
  .service` produced zero journal output and never completed startup
  across 5+ restart cycles (~5 minutes) of real testing. Root cause not
  identified (suspected `libsignal-ffi` blocking on network access
  before logging anything).
- **Telegram bridge** and the **cross-service integration test**: both
  `test-bridge-telegram` and `test-bridge-integration` are confirmed
  passing in a real VM run. Getting there surfaced two real
  bugs, not just an environment/resource issue: (1) the Telegram bridge's
  nixpkgs module uses `DynamicUser`, whose state directory is only
  reachable via a root-only `/var/lib/private/` indirection — fixed by
  giving it a static user/group, the same pattern the WhatsApp bridge
  already uses; (2) the module tried to write its generated appservice
  token back into a path in the read-only Nix store, failing silently and
  crash-looping the bridge — fixed with a wrapper that merges the token
  into a writable config copy before the bridge starts.
- CI matrix (24.05 + unstable) needs real GitHub Actions runners — local
  checks already pass, but the repo isn't published yet.
- Dendrite support is scaffolded, not exercised by any test.
- nixpkgs PR not yet submitted — module meta is ready, but needs a real
  registered nixpkgs maintainer entry and a push to open it.

## Methodology note

Every fix listed above was found via an actual `nix build`/NixOS VM test
failure in a real WSL2+Nix+KVM environment — not by static code review
alone. Where something couldn't be verified end-to-end (Signal), that is
stated explicitly, with the specific evidence for and against, rather
than assumed working.
