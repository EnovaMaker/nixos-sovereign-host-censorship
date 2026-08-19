# Quickstart

## Install

```nix
{
  inputs.sovereign-host.url = "github:EnovaMaker/nixos-sovereign-host";

  outputs = { nixpkgs, sovereign-host, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        sovereign-host.nixosModules.sovereign-host
        ./configuration.nix
      ];
    };
  };
}
```

## Configure — funded scope (Matrix + bridges + Syncthing)

```nix
{
  services.sovereign = {
    enable = true;
    matrix = {
      enable = true;
      domain = "matrix.example.org";
      enableTls = true;              # real ACME cert via nginx
      adminEmail = "admin@example.org";
      bridge.whatsapp.enable = true; # confirmed working end-to-end in a VM test
      # bridge.telegram.enable = true;  # confirmed passing in a real VM run
      # bridge.signal.enable = true;    # best-effort — see the warning below
    };
    syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
    };
  };
}
```

Enabling *any* bridge (whatsapp/signal/telegram) pulls in `libolm`,
which nixpkgs marks insecure (deprecated upstream, CVE-2024-45191/2/3).
You'll see a build error unless you explicitly accept that:

```nix
{ nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ]; }
```

Make an informed call before doing so — see `docs/ROADMAP.md` for what
was actually found while testing each bridge.

## Secrets (OIDC/TURN/bridge credentials)

Every secret in this module is file-based — nothing sensitive is ever
written into the Nix store:

```nix
{
  services.sovereign.matrix = {
    sso.enable = true;
    sso.clientSecretFile = config.sops.secrets.matrix-oidc-secret.path;
    turn.enable = true;
    turn.sharedSecretFile = config.sops.secrets.matrix-turn-secret.path;
    bridge.telegram.environmentFile = config.sops.secrets.telegram-bridge-env.path;
  };
}
```

Rotating a credential is just: update the sops-nix/agenix-managed file,
then restart the affected service (`systemctl restart matrix-synapse` /
`mautrix-<bridge>` / `coturn`). Each bridge's own `preStart` re-reads its
`environmentFile` on every start, not just the first, so this always
picks up the new value. Point sops-nix's `restartUnits` at the relevant
service to make this automatic on rotation instead of manual.

## Optional bonus modules (not part of the funded scope)

`monitoring`, `backup`, and `sso` overlap with
[`ibizaman/selfhostblocks`](https://github.com/ibizaman/selfhostblocks)
(already NLnet-funded) — included in this repo and tested, but not
billed as part of this grant. Compose with Self Host Blocks instead if
you want a maintained, funded monitoring/backup/SSO stack; use these
modules if you'd rather have one flake for everything.

## Known limitations

- Signal bridge: excluded from VM testing entirely — separately from the
  libolm issue above, `mautrix-signal.service` produced zero journal
  output and never completed startup across 5+ minutes of real testing
  in this environment. Best-effort.
- Telegram bridge and the Matrix+bridge+Syncthing integration test: both
  confirmed passing in a real VM run — see `docs/FINAL_REPORT.md`
  for the two real bugs found and fixed along the way.
