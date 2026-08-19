# Roadmap — nixos-sovereign-host

> Private tree — full implementation, kept private until milestones are
> claimed post-GA. Funded scope is Matrix + bridges + Syncthing; monitoring/
> backup/SSO ship as an unfunded bonus (see the NLnet proposal for detail).

## Phase 1 — Foundation ✅ done
- [x] Module architecture design
- [x] flake.nix with all module imports
- [x] Matrix module: Synapse + Dendrite + bridges (WhatsApp, Signal, Telegram) + TLS
- [x] Syncthing module: declarative devices + folders
- [x] Monitoring module: Prometheus + Grafana + Alertmanager dashboards (bonus)
- [x] Backup module: Borg + restic (bonus)
- [x] SSO module: Authelia OIDC (bonus)
- [x] NixOS VM test suite covering all five modules + a full-stack integration test
- [x] CI matrix (24.05 + unstable)
- [x] Real bugs found and fixed in review (mkIf/// merge bug, backup passphrase collision, Syncthing TLS/restart)

## Phase 2 (meses 1-4) — M1: Matrix + Syncthing hardened
- [ ] Matrix: real test coverage for SSO/TURN integration (post-bugfix), edge-case coverage
- [ ] Syncthing: NAT/relay edge cases
- [ ] CI green across NixOS 24.05 + unstable

## Phase 3 (meses 5-7) — M2: bridge coverage + integration
- [x] Bridge Synapse registration: found via real VM testing that only
      mautrix-signal's module has the registerToSynapse auto-wiring option
      in this pinned nixpkgs (24.05) — whatsapp/telegram do not, so both
      ran but were completely invisible to Synapse (401 on every request).
      Wired manually in matrix.nix + fixed the DynamicUser permission gap
      for telegram + the SupplementaryGroups/systemd-sysusers ordering
      race. See git log for the full bug list.
- [x] test-bridge-whatsapp: passes end-to-end in a real NixOS VM test
      (registration generated, wired into Synapse, request reaches auth layer)
- [x] test-bridge-telegram: confirmed passing in a real VM run,
      after fixing two real bugs found along the way — the
      module's `DynamicUser` made its state directory unreachable to
      other services by systemd design (fixed with a static user/group,
      same pattern as whatsapp), and it tried to write its generated
      appservice token into a read-only Nix store path (fixed with a
      wrapper that merges it into a writable config copy). See
      `docs/FINAL_REPORT.md` for detail.
- [ ] Signal: excluded from VM testing — separately from the libolm
      insecure-package issue, mautrix-signal.service produced zero journal
      output and never completed startup across 5+ restart cycles of real
      testing. Best-effort/unverified (see matrix.nix warning).
- [x] sops-nix/agenix wiring for OIDC/TURN secrets — replaced the literal
      `<sops>`/`<sops-turn>` placeholders (which landed in /nix/store
      world-readable if ever filled with a real secret) with Synapse's
      own `client_secret_path`/`turn_shared_secret_path` and coturn's
      `static-auth-secret-file` — all three read the secret from a file
      at their own runtime, confirmed against each project's actual
      source, never embedded in the generated config. New warnings fire
      when SSO/TURN are enabled without the corresponding file set.
      Bridge secrets (WhatsApp/Telegram `environmentFile`, Telegram
      `api_id`/`api_hash`) were already file-based from the M2 bridge
      work above — this closes the remaining two (OIDC, TURN).
- [x] Bridge credential rotation — confirmed via the actual nixpkgs
      bridge module source (not assumed): each bridge's `preStart` (which
      does the `envsubst` substitution from `environmentFile`) runs on
      *every* service start, not just the first — so rotation is just
      "update the sops-nix/agenix-managed file, then `systemctl restart
      <bridge>.service`" for whatsapp/telegram, and the same for
      Synapse/coturn's `*_secret_path`/`*-secret-file` options added
      above. No new module code needed — it already works this way.
      Operator-side: point the file at a sops-nix secret with
      `restartUnits = [ "mautrix-whatsapp.service" ... ]` set so a secret
      rotation triggers the restart automatically instead of needing a
      manual one.
- [ ] Bridge reconnection edge cases (WhatsApp/Telegram) — each bridge's
      own `Restart = "always"`/`"on-failure"` (set by its nixpkgs module,
      not ours) already covers basic reconnection; deeper edge cases
      (e.g. a bridge's own session expiring vs. Synapse being briefly
      unreachable) not specifically tested this pass.
- [x] Cross-service integration test (Matrix + bridge + Syncthing) —
      `test-bridge-integration`, confirmed passing in a real VM run
      together with `test-bridge-telegram` (see the two real
      bugs fixed along the way — `DynamicUser`/StateDirectory visibility
      and the Nix-store-path token write — in `docs/FINAL_REPORT.md`).

## Phase 4 (meses 8-10) — M3: upstream + delivery
- [~] nixpkgs PR for the Matrix + Syncthing modules — module ready but not
      submitted: needs a real registered nixpkgs maintainer entry and a
      push to actually open it.
- [x] Documentation EN + PT — `docs/QUICKSTART.md` + `docs/QUICKSTART.pt.md`.
- [~] Demo deployment on a community-operated VPS — `examples/demo-host.nix`
      is now a real, deployable NixOS host (boot/disk/SSH/firewall +
      Matrix + WhatsApp bridge + Syncthing, the funded scope). Confirmed
      by building the full system closure (`nixosConfigurations.demo`) —
      genuinely contains `matrix-synapse.service`,
      `mautrix-whatsapp.service`, `syncthing.service`, and the ACME
      units. Only remaining blocker: a real VPS + DNS to point
      `nixos-rebuild --target-host` at, and the repo push itself.
- [x] Community operator guide, including composing with Self Host Blocks
      for monitoring/backup/SSO — covered in `docs/QUICKSTART.md`'s
      "Optional bonus modules" section.
- [x] Final report — `docs/FINAL_REPORT.md`.

## Best-effort (não bloqueia)
- [ ] Dendrite support (Synapse alternative)
- [ ] Merge do PR nixpkgs

> Milestones e percentagens de pagamento conforme a proposta NLnet.
