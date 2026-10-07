# Architecture — censorship-resilience layer

> Design document. No implementation in this tree.

## Where this sits

```
  services.sovereign.censorship.*      ← this layer
            │
            ├── configures ──►  services.tor            (nixpkgs, upstream)
            │
            └── publishes  ──►  services.sovereign.matrix
                                services.sovereign.syncthing
                                services.sovereign.sso
                                services.sovereign.monitoring
```

Two rules shape every decision below:

1. **Configure upstream, never replace it.** Options live under `services.sovereign.censorship`
   and drive nixpkgs' own `services.tor`. As that module's source shows, `relay.role = "bridge"` already
   configures obfs4 via `mkDefault`, so this layer will not duplicate that logic.
2. **Reachability is not security.** This layer keeps a deployment reachable under network
   blocking. It does not protect a compromised host, and it does not eliminate the metadata
   the Matrix protocol leaks by design.

## Onion publishing

Each service opts in independently. All toggles default to `false`, including Matrix: a default
of `true` would make a safety assertion fail whenever Matrix itself is disabled.

The homeserver is published as an onion service for the **client API**. Federation over onion
is deliberately out of scope: Matrix federation assumes reachable, discoverable servers, and
pretending otherwise would mislead an operator.

## Bridge relay

An obfs4 bridge contributes capacity to the shared Tor network. A bridge, unlike an exit
relay, performs no exit to the open internet — so it generates no abuse complaints and needs
no incident-handling process, which is what makes it realistic for a small operator to run.

Design consequence worth stating: a public bridge is discoverable by design. obfs4 resists
deep packet inspection but does not make a bridge unenumerable. The defence is aggregate
network capacity, not secrecy about any single relay.

## Metadata hardening

A `highRiskMode` reduces what the stack retains about its users. This created a genuine
conflict during design: reduced logging is exactly what you want for user privacy, and exactly
what you do not want when you must later prove the relay ran for an audit.

The design separates the two concerns rather than compromising either:

- **Tor's own aggregate statistics** (`ExtraInfoStatistics`, `DirReqStatistics`,
  `BridgeRecordUsageByCountry`) — designed by the Tor Project for this purpose, never
  sensitive to individual privacy.
- **A dedicated uptime record**, containing no user data, written by service start/stop hooks
  and therefore never subject to the log reduction in the first place.

The record covers whenever Tor runs, not only when the bridge relay is enabled: tying it to
the relay would leave onion-only deployments with no evidence at all.

## Lockdown

One option forces onion-only reachability together with metadata hardening. Two properties
matter more than the feature itself:

- **Reversible.** NixOS' atomic generations mean `nixos-rebuild switch --rollback` undoes it.
  An operator triggering this under pressure must be able to undo it under pressure.
- **The bridge stays up.** Lockdown removes clearnet reachability of *services*; it must not
  take down the relay, which serves the wider network rather than this deployment.

## Upstream

One contribution is planned back into nixpkgs: a typed
`services.tor.settings.ServerTransportListenAddr` option. The freeform type already accepts
the value today — the gap is that it is untyped and undocumented, unlike its sibling
`ServerTransportPlugin` in the same file.

## Verification approach

Design intent is that every guarantee above is exercised by a NixOS VM test against the exact
nixpkgs revision this design targets, not a newer channel — including a two-node test where a second
machine attempts the clearnet port under lockdown and must be refused while the bridge port
stays reachable.
