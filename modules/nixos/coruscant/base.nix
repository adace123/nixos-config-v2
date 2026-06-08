{ ... }:
{
  imports = [
    ../common.nix
    ./home-assistant.nix
  ];

  networking = {
    hostName = "coruscant";
    useDHCP = true;

    firewall = {
      enable = true;
      trustedInterfaces = [ "tailscale0" ];
      allowedTCPPorts = [
        8123 # Home Assistant Web UI
      ];
      allowedUDPPorts = [ 5353 ]; # mDNS
    };
  };

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

  time.timeZone = "UTC";
}
