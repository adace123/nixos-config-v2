{ ... }: {
  imports = [
    ./common.nix
    ./home-assistant.nix
  ];

  networking.hostName = "coruscant";
  networking.useDHCP = true;

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

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-partlabel/root";
      fsType = "ext4";
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-partlabel/firmware";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };
  };

  time.timeZone = "UTC";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      8123
      1883
      8091
    ];
    allowedUDPPorts = [ 5353 ];
  };
}
