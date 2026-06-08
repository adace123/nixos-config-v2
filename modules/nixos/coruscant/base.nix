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
      allowedTCPPorts = [
        8123
        1883
        8091
      ];
      allowedUDPPorts = [ 5353 ];
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
