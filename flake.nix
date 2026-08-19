{
  description = "nixos-sovereign-host: Declarative self-sovereign hosting stack for communities";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, flake-utils }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
      nixpkgsUnstableFor = forAllSystems (system: import nixpkgs-unstable { inherit system; });
    in
    {
      nixosModules = {
        sovereign-host = import ./modules;
        matrix = import ./modules/matrix.nix;
        syncthing = import ./modules/syncthing.nix;
        monitoring = import ./modules/monitoring.nix;
        backup = import ./modules/backup.nix;
        sso = import ./modules/sso.nix;
      };

      nixosModule = self.nixosModules.sovereign-host;

      # M3 demo deployment target — a real, deployable host config (boot,
      # disk, SSH, firewall), not just a module-options snippet. See
      # examples/demo-host.nix for the CHANGE ME markers a real VPS needs.
      nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ self.nixosModules.sovereign-host ./examples/demo-host.nix ];
      };

      overlays.default = final: prev: {
        sovereign-host-cli = final.callPackage ./cli { };
      };

      packages = forAllSystems (system: {
        sovereign-host-cli = nixpkgsFor.${system}.callPackage ./cli { };
        default = self.packages.${system}.sovereign-host-cli;
        # Options documentation — proves the module tree evaluates under the
        # full NixOS module system (assertions/warnings included).
        docs = (nixpkgsFor.${system}.nixosOptionsDoc {
          options = (nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [ self.nixosModules.sovereign-host ];
          }).options.services.sovereign;
        }).optionsJSON;
      });

      checks = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          pkgs-unstable = nixpkgsUnstableFor.${system};
          lib = pkgs.lib;
        in
        {
          cli = pkgs.callPackage ./cli { };

          test-matrix = pkgs.releaseTools.aggregate {
            name = "test-matrix";
            constituents = [
              self.checks.${system}.test-synapse
              self.checks.${system}.test-syncthing
              self.checks.${system}.test-syncthing-no-relay
              self.checks.${system}.test-matrix-sso-turn
              self.checks.${system}.test-monitoring
              self.checks.${system}.test-backup
              self.checks.${system}.test-sso
              self.checks.${system}.test-bridge-whatsapp
              self.checks.${system}.test-bridge-telegram
              self.checks.${system}.test-bridge-integration
              self.checks.${system}.test-full-stack
            ];
          };

          test-synapse = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-synapse;
          test-syncthing = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-syncthing;
          test-syncthing-no-relay = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-syncthing-no-relay;
          test-matrix-sso-turn = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-matrix-sso-turn;
          test-monitoring = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-monitoring;
          test-backup = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-backup;
          test-sso = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-sso;
          test-bridge-whatsapp = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-bridge-whatsapp;
          test-bridge-telegram = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-bridge-telegram;
          test-bridge-integration = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-bridge-integration;
          test-full-stack = (import ./tests { inherit pkgs pkgs-unstable lib; }).test-full-stack;
        }
      );

      devShells = forAllSystems (system: {
        default = nixpkgsFor.${system}.mkShell {
          packages = with nixpkgsFor.${system}; [
            nixos-generators
            nixfmt
          ] ++ [ self.packages.${system}.sovereign-host-cli ];
          shellHook = ''
            echo "nixos-sovereign-host dev shell — Matrix, Syncthing, Monitoring, Backup, SSO"
          '';
        };
      });
    };
}
