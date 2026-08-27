# Roadmap — censorship-resilience layer

> Design preview. Milestone numbering follows the proposal to the Open Technology Fund's
> Internet Freedom Fund. Months are relative to a funded start, not calendar dates.

| Milestone | Months | Guaranteed core |
|---|---|---|
| **M1** | 1-3 | Onion service for the Matrix client API, hardened: broader test matrix, edge-case handling, operator documentation refined against real deployment |
| **M2** | 4-6, relay runs to 12 | Public obfs4 bridge relay in real operation for the shared Tor network, with the privacy-preserving uptime and statistics record; metadata hardening finalized |
| **M3** | 6-8 | Onion reachability extended to file sync, SSO and monitoring; one-flag lockdown forcing onion-only, reversible via `nixos-rebuild switch --rollback` |
| **M4** | 8-10 | Guard-discovery hardening for long-lived onion services: a NixOS module for the Tor Project's `vanguards` add-on, wired to the running Tor's control port and applied to the onion services this layer publishes |
| **M5** | 10-12 | External security review and remediation; the typed `ServerTransportListenAddr` option contributed upstream to nixpkgs; operator documentation EN/PT; final report |

## Why M4 is not redundant

Tor has shipped **vanguards-lite** natively since 0.4.7, and the version pinned here is
0.4.8.13 — so it is already in use. But vanguards-lite omits the third layer of guards, and the
Tor Project's guidance is that it protects services *"around for a month or less"*, while
*"longer lived onion services are still encouraged to use the vanguards addon"*. A community
Matrix homeserver is long-lived by definition.

The add-on is packaged in nixpkgs but not in the revision this project pins, and no NixOS
module for it exists anywhere.

**Stated rather than hidden:** the add-on's last release activity was July 2024. It is not
archived, it is authored by a core Tor developer, and it remains the Tor Project's standing
recommendation for this case — but a dependency that has been quiet for two years is a risk an
operator deserves to be told about, and documenting exactly that is part of the milestone.

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
- **WebTunnel.** A different operating model rather than another transport on the same relay:
  an obfs4 bridge needs a port and a running Tor, while a WebTunnel bridge needs a registered
  domain, a valid certificate and a web server in front of it. Nothing here touches it.
- **Onion-service availability and monitoring.** This layer publishes services as onion
  services and hardens them against guard discovery. It does not make them highly available
  across multiple instances, and it does not monitor published onion addresses for external
  reachability.
- **Protecting a compromised host.** This layer addresses reachability under blocking. Nothing
  here defends a server whose operator has already been compromised.

## Relationship to `nixos-sovereign-host`

This layer builds on the module framework published at
[`nixos-sovereign-host`](https://github.com/EnovaMaker/nixos-sovereign-host) and is funded
separately, by a different funder, for a different layer. The two share a codebase but no
budget line, and neither milestone set depends on the other.
