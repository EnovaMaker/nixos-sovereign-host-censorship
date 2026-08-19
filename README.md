# nixos-sovereign-host

Declarative self-sovereign hosting stack for communities.

## Quick start

```nix
{
  inputs.sovereign-host.url = "github:EnovaMaker/nixos-sovereign-host";

  outputs = { self, nixpkgs, sovereign-host }: {
    nixosConfigurations.my-server = nixpkgs.lib.nixosSystem {
      modules = [
        sovereign-host.nixosModules.sovereign-host
        {
          services.sovereign = {
            enable = true;
            matrix.enable = true;
            syncthing.enable = true;
            monitoring.enable = true;
            backup.enable = true;
            sso.enable = true;
          };
        }
      ];
    };
  };
}
```

## Architecture

```
sovereign (services.sovereign.enable = true)
├── matrix     — Synapse + bridges + TLS
├── syncthing  — P2P file sync
├── monitoring — Prometheus + Grafana
├── backup     — Borg/restic automation
└── sso        — Authelia OIDC
```

All modules work independently or together with zero-config integration.

## License

MIT
