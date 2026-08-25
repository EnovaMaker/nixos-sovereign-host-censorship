{
  description = "nixos-sovereign-host-censorship: Tor onion services, obfs4 bridge relay and lockdown mode for NixOS (design preview — no buildable code in this tree, see docs/)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # This preview tree intentionally ships no modules/cli/tests (see README:
  # "Design phase"). Do not add nixosModules/packages outputs here unless the
  # referenced files actually exist in this tree — a sibling project
  # (CodeSupply) had this exact bug: referencing ./modules paths that were
  # never copied in, which broke `nix flake check`.
  outputs = { self, nixpkgs, flake-utils }: { };
}
