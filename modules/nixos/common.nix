{ config, ... }:
{
  # System state version
  system.stateVersion = "24.11";

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC6DWf0lf4vWTAUmjkulvvZrhCifTS8eFqkDlHPSawrU"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILRSOuLiLN+rY14q+55fd7XUH3rfA54nx3gZJjfmwa7G"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH6NoE7HzOLf05FzjkbsQQkMSbe6AJEm2fgNZeaO6RAe"
  ];

  # Enable automatic updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    flags = [
      "--flake"
      ".#${config.networking.hostName}"
    ];
  };

  # Enable garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Nix settings for better performance
  nix.settings = {
    auto-optimise-store = true;
    max-jobs = 4;
    cores = 4;
    extra-substituters = [
      "https://cache.numtide.com"
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  # Networking — DHCP on all interfaces
  networking.useDHCP = true;

  # Firewall — trust tailscale and allow mDNS for local discovery
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 5353 ];
  };

  # mDNS / Avahi for local service discovery
  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      workstation = true;
      addresses = true;
      domain = true;
    };
  };

  # Timezone
  time.timeZone = "America/Los_Angeles";

  # Enable NTP
  services.ntp = {
    enable = true;
    servers = [ "pool.ntp.org" ];
  };

  # Enable log rotation
  services.logrotate.enable = true;

  # Configure journald for persistent logging
  services.journald = {
    extraConfig = ''
      Storage=persistent
      MaxRetentionSec=1month
    '';
  };

  # Tailscale for secure remote access
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  # ZRAM swap configuration
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
