# nixos-sovereign-host-censorship

Censorship-resilience layer for [`nixos-sovereign-host`](https://github.com/EnovaMaker/nixos-sovereign-host) — declarative Tor onion services, an obfs4 bridge relay, metadata hardening, and a one-flag lockdown mode, for NixOS.

> **Design phase.** This tree documents the architecture only. It intentionally ships no
> modules, CLI or tests — see `docs/ARCHITECTURE.md` for the design and `docs/ROADMAP.md` for
> what is planned and in what order.

## The problem

Operators of independent, self-hosted communication infrastructure — community groups,
independent media, diaspora organizers — have no declarative, tested way to stay reachable
when their domain or IP range is blocked. Today that work is manual, ad-hoc and undocumented,
and it demands specialist networking knowledge most small operators do not have.

The result is that self-hosting, otherwise a meaningful path to digital sovereignty, becomes a
single point of failure the moment a government decides to block it.

## What this layer adds

Built on top of the existing `services.sovereign.*` modules, and on nixpkgs' own
`services.tor` rather than around it:

| Capability | What it does |
|---|---|
| **Onion publishing** | Reach the Matrix client API — and optionally file sync, SSO and monitoring — over Tor onion services, from a single declarative option |
| **obfs4 bridge relay** | Contribute circumvention capacity to the shared Tor network, not only to your own users |
| **Metadata hardening** | Reduce what the stack logs about its users, deliberately and by default |
| **Lockdown mode** | One flag forces onion-only reachability and hardening together, reversible with `nixos-rebuild switch --rollback` |
| **Auditable uptime** | A privacy-preserving record that the relay actually ran, using Tor's own aggregate statistics — designed so it survives metadata hardening |

## What it is not

- **Not a fork of Tor tooling.** The Tor Project's onion services and the obfs4 pluggable
  transport are the primitives; we do not reimplement either.
- **Not a replacement for `services.tor`.** nixpkgs already ships a mature module and we
  configure it. As its source shows, `relay.role = "bridge"` already sets up obfs4
  by default, so this layer will not duplicate that logic.
- **Not a claim that your server is safe.** This makes a deployment *reachable under network
  blocking*. That is a different thing from secure, and conflating the two would be
  irresponsible toward anyone whose safety depends on it.

## Status

Design preview. Architecture and roadmap are in `docs/`.

## License

[MIT](LICENSE)
