# Real, deployable NixOS host — not a module-option snippet like
# examples/configuration.nix. This is everything a bare cloud VPS needs
# to become the M3 demo host: boot, disk, SSH, firewall, and the actual
# service. The only things you cannot fill in without a real server/domain
# are marked CHANGE ME below — everything else is ready as-is.
#
# NB: the sovereign-host module is imported by flake.nix's
# nixosConfigurations.demo, not here — importing it in both places
# double-declares every option (same bug already found and fixed while
# building an equivalent demo host for a sibling project).
#
# Deploy: point `nixos-rebuild switch --flake .#demo --target-host
# root@<server-ip>` at a fresh NixOS install (or use nixos-anywhere for a
# from-scratch provider image), then `nixos-rebuild switch` on the box.
{ config, pkgs, lib, ... }:

{
  # --- CHANGE ME: boot + disk — depends on the VPS provider's image ---
  # Most cloud providers (Hetzner, DigitalOcean, Vultr, ...) hand you a
  # single virtio/scsi disk and boot via UEFI on current images. Adjust
  # the device path and boot mode to match what `lsblk`/`efibootmgr`
  # shows on the actual box.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos"; # CHANGE ME if not using a labeled partition
    fsType = "ext4";
  };

  # --- CHANGE ME: identity ---
  networking.hostName = "sovereign-demo"; # CHANGE ME
  time.timeZone = "UTC";

  # --- SSH: key-only, no root password login ---
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAA...CHANGE-ME your-key-comment" # CHANGE ME
  ];

  # --- All three mautrix bridges depend on libolm, which nixpkgs marks
  # insecure (CVE-2024-45191/2/3). Only whatsapp is enabled below (the
  # one bridge confirmed working end-to-end in a VM test), but the
  # override is still needed to build it at all — confirmed via an
  # actual build attempt, see docs/ROADMAP.md.
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  # --- The actual demo: Matrix + WhatsApp bridge + Syncthing (the
  # funded scope) ---
  services.sovereign = {
    enable = true;
    matrix = {
      enable = true;
      domain = "matrix.example.org"; # CHANGE ME: needs real DNS pointed here for ACME to work
      enableTls = true;
      adminEmail = "admin@example.org"; # CHANGE ME
      bridge.whatsapp.enable = true;
      # sso/turn secrets are file-based (see docs/QUICKSTART.md) —
      # deliberately left unset here; the module warns rather than
      # silently running unauthenticated if you enable sso/turn without
      # also setting sso.clientSecretFile/turn.sharedSecretFile.
    };
    syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384"; # bind to localhost; reach it over SSH port-forward, not publicly
    };
    # monitoring/backup/sso are bonus modules (overlap with the already
    # NLnet-funded selfhostblocks) — left disabled here since they're
    # not part of what this grant funds; enable if you want them anyway.
  };

  networking.firewall.allowedTCPPorts = [ 22 80 443 8448 ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.05"; # matches this flake's pinned nixpkgs — do not change without a real upgrade
}
