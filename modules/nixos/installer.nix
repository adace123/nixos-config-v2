{
  host,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./common.nix
  ];

  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building the vendor kernel from source under QEMU emulation.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Installer image — disable services that don't apply to a temporary image
  system.autoUpgrade.enable = lib.mkForce false;
  nix.gc.automatic = lib.mkForce false;
  virtualisation.docker.enable = lib.mkForce false;
  services.tailscale.enable = lib.mkForce false;
  zramSwap.enable = lib.mkForce false;

  networking.hostName = "${host.hostName}-installer";

  # Installer image: allow root login with password for initial setup
  services.openssh.settings = lib.mkForce {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };
  users.users.root.initialPassword = "installer";

  # Override avahi hostname to match the installer hostname
  services.avahi.hostName = "${host.hostName}-installer";

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
}
