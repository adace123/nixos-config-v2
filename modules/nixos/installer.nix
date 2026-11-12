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

  # Installer image: key-only SSH with the keys the hosts already authorize
  # (hosts/rpi-keys.nix). The old `root:installer` account was a credential
  # printed in this public repo and listening on the LAN, so a booted card left
  # in a drawer was root for anyone. `just nixos-init` authenticates through the
  # SSH agent (NIXOS_INIT_KEY points at a specific identity file if needed).
  services.openssh.settings = lib.mkForce {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
  };

  # Override avahi hostname to match the installer hostname
  services.avahi.hostName = "${host.hostName}-installer";

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
}
