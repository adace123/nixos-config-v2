{ ... }:
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

  # Enable automatic updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = true;
    flags = [
      "--flake"
      ".#coruscant"
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
  };

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

  # Docker for additional containers (optional)
  virtualisation.docker.enable = true;

  # Tailscale for secure remote access
  # After first boot, authenticate with: tailscale up
  # Or set services.tailscale.authKeyFile for automated auth.
  services.tailscale = {
    enable = true;
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  # ZRAM swap configuration
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
