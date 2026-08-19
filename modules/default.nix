{ lib, config, pkgs, ... }:

let
  cfg = config.services.sovereign;
  inherit (lib) mkEnableOption mkIf;
in
{
  imports = [
    ./matrix.nix
    ./syncthing.nix
    ./monitoring.nix
    ./backup.nix
    ./sso.nix
  ];

  options.services.sovereign = {
    enable = mkEnableOption "sovereign-host self-hosting stack";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ (pkgs.sovereign-host-cli or (pkgs.callPackage ../cli { })) ];
  };
}