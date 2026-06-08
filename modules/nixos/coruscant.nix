{ ... }:
{
  imports = [
    ./common.nix
    ./home-assistant.nix
  ];

  # Hostname configuration
  networking.hostName = "coruscant";
  networking.useDHCP = true;

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
