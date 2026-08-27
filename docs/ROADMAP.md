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

## Stated rather than hidden

The add-on's last commit is **October 2023**, and its author has since moved to unrelated work.
Three separate attempts to establish whether it is still maintained went unanswered: on IRC, on
the `tor-relays` list in July 2026, and in an issue open since November 2023. It is not archived
and it remains the Tor Project's standing recommendation for long-lived onion services, but
nobody will confirm its status either way.

There is also an open interaction bug worth naming:
[`tpo/core/tor#40892`](https://gitlab.torproject.org/tpo/core/tor/-/issues/40892), *"Tor 0.4.8.9
broken in combination with vanguards"*, open since November 2023. Connections drop mid-transfer
when vanguards is running — reproducibly under Qubes PVH, KVM and VirtualBox, not on bare metal.
Reports conflict: the reporter still saw it on 0.4.8.12, while a Tor Project member could not
reproduce it on Debian under KVM. Most VPS hosting is KVM, so the ambiguity sits across exactly
the kind of deployment this layer targets.

**So this milestone commits to settling it rather than hoping.** In that thread Roger Dingledine
asked for a `git bisect`, and the reporter replied that setting up a test environment was too
labour-intensive and invited anyone else to try. Nobody has, in almost three years — the missing
piece is reproducible test infrastructure, which is what this project already builds. We promise
the test and the report, not a particular finding: if the interaction reproduces on the revision
we pin, the Tor Project gets the reproduction it asked for; if it does not, a three-year-old
question gets a documented answer.

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
