{ ... }:
{
  imports = [
    ./common.nix
    ./home-assistant.nix
  ];

  # Hostname configuration
  networking.hostName = "coruscant";
  networking.useDHCP = true;

  sops = {
    defaultSopsFile = ../secrets/default.yaml;
    age.keyFile = "/var/lib/sops/age-key.txt";
    secrets."wpa-supplicant" = {
      neededForUsers = true;
    };
  };

  # WiFi (wpa_supplicant) — SSID/PSK from sops secret loaded at runtime.
  # Used as fallback when Ethernet is unavailable.
  networking.wireless = {
    enable = true;
    extraConfigFiles = [
      "/run/secrets/wpa-supplicant"
    ];
  };

  # Ensure wpa_supplicant has the secrets before starting
  systemd.services.wpa_supplicant = {
    wants = [ "sops-init.service" ];
    after = [ "sops-init.service" ];
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
