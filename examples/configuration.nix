# Example: enable the full sovereign-host stack on a NixOS host.
# Matrix + Syncthing are the Restack-funded core; monitoring/backup/sso are
# bonus modules, already built, not part of the funded scope.
{ config, pkgs, lib, ... }:

{
  imports = [ (import ../modules) ];

  services.sovereign = {
    enable = true;

    matrix = {
      enable = true;
      domain = "example.org";
      # bridge.whatsapp.enable = true;
      # bridge.signal.enable = true;
      # bridge.telegram.enable = true;
    };

    syncthing = {
      enable = true;
      # devices = { ... };
      # folders = { ... };
    };

    monitoring.enable = true; # bonus, not grant-funded
    backup.enable = true;     # bonus, not grant-funded
    sso.enable = true;        # bonus, not grant-funded
  };
}
