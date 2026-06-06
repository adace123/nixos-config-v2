{ lib, ... }:
{
  imports = [
    ./common.nix
    ./home-assistant.nix
  ];

  # Hostname configuration
  networking.hostName = "coruscant";
  networking.useDHCP = true;

  # WiFi warning when env vars are not set
  warnings = lib.optional (builtins.getEnv "WIFI_SSID" == "") ''
    WiFi is not configured. Set WIFI_SSID and WIFI_PSK environment variables
    at build time to enable wireless networking (e.g. WIFI_SSID=MyNetwork WIFI_PSK=secret just nixos-deploy).
    The Pi will use Ethernet only.
  '';

  # WiFi (wpa_supplicant) — set WIFI_SSID and WIFI_PSK env vars at build time.
  # Used as fallback when Ethernet is unavailable.
  networking.wireless = lib.mkIf (builtins.getEnv "WIFI_SSID" != "") {
    enable = true;
    networks."${builtins.getEnv "WIFI_SSID"}" = {
      psk = builtins.getEnv "WIFI_PSK";
    };
  };

  # Enable mDNS for local network discovery
  services.avahi = {
    enable = true;
    hostName = "coruscant";
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

  # Configure firewall for Home Assistant
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8123
      1883
      8091
    ]; # Home Assistant, MQTT, Zigbee2MQTT
    allowedUDPPorts = [ 5353 ]; # mDNS
  };

}
