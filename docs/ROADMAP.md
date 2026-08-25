# Roadmap — censorship-resilience layer

> Design preview. Milestone numbering follows the proposal to the Open Technology Fund's
> Internet Freedom Fund. Months are relative to a funded start, not calendar dates.

| Milestone | Months | Guaranteed core |
|---|---|---|
| **M1** | 1-3 | Onion service for the Matrix client API, hardened: broader test matrix, edge-case handling, operator documentation refined against real deployment |
| **M2** | 4-6, relay runs to 12 | Public obfs4 bridge relay in real operation for the shared Tor network, with the privacy-preserving uptime and statistics record; metadata hardening finalized |
| **M3** | 6-9 | Onion reachability extended to file sync, SSO and monitoring; one-flag lockdown forcing onion-only, reversible via `nixos-rebuild switch --rollback` |
| **M4** | 9-12 | External security review and remediation; the typed `ServerTransportListenAddr` option contributed upstream to nixpkgs; operator documentation EN/PT; final report |

## Best-effort, not guaranteed

**Snowflake pluggable transport.** Stated precisely, because the distinction matters:
`pkgs.snowflake` (2.9.2, the Tor Project's own) **is** available at the nixpkgs revision this
project pins. What does not exist is any declarative way to run it — `services.tor` exposes no
snowflake option at all, unlike obfs4, which is wired the moment `relay.role = "bridge"` is
set. Adding it means building the server-side integration from scratch and operating a second
transport, so it is offered as best-effort rather than promised.

**Community validation.** Reviewing the operator guidance with the Tor Project's own
anti-censorship community.

## Out of scope, deliberately

- **Federation over onion.** Matrix federation assumes reachable, discoverable servers.
- **meek.** Largely abandoned as a transport; promising support for something on its way out
  would be a credibility cost, not a feature.
- **Protecting a compromised host.** This layer addresses reachability under blocking. Nothing
  here defends a server whose operator has already been compromised.

## Relationship to `nixos-sovereign-host`

This layer builds on the module framework published at
[`nixos-sovereign-host`](https://github.com/EnovaMaker/nixos-sovereign-host) and is funded
separately, by a different funder, for a different layer. The two share a codebase but no
budget line, and neither milestone set depends on the other.
