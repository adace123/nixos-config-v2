{ lib, pkgs, ... }:
{
  # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
  # to avoid building the vendor kernel from source under QEMU emulation.
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  imports = [
    ./common.nix
  ];

  networking.hostName = "coruscant-installer";
  networking.useDHCP = true;

  # WiFi warning when env vars are not set
  warnings = lib.optional (builtins.getEnv "WIFI_SSID" == "") ''
    WiFi is not configured. Set WIFI_SSID and WIFI_PSK environment variables
    at build time to enable wireless networking.
  '';

  # WiFi (wpa_supplicant) — set WIFI_SSID and WIFI_PSK env vars at build time.
  networking.wireless = lib.mkIf (builtins.getEnv "WIFI_SSID" != "") {
    enable = true;
    networks."${builtins.getEnv "WIFI_SSID"}" = {
      psk = builtins.getEnv "WIFI_PSK";
    };
  };

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
