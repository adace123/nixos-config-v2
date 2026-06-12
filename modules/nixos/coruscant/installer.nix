{ lib, pkgs, ... }:
{
  imports = [
    ../common.nix
  ];

  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building the vendor kernel from source under QEMU emulation.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  boot.loader.raspberry-pi.bootloader = "kernel";

  networking.hostName = "coruscant-installer";
  networking.useDHCP = true;

  # Installer image: allow root login with password for initial setup
  services.openssh.settings = lib.mkForce {
    PermitRootLogin = "yes";
    PasswordAuthentication = true;
  };
  users.users.root.initialPassword = "installer";

  # Enable mDNS for local network discovery
  services.avahi = {
    enable = true;
    hostName = "coruscant-installer";
    publish = {
      enable = true;
      workstation = true;
      addresses = true;
      domain = true;
    };
  };

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # Timezone
  time.timeZone = "UTC";

  # Minimal firewall — just mDNS
  networking.firewall = {
    enable = true;
    allowedUDPPorts = [ 5353 ];
  };
}
