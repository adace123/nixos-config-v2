{ host, ... }:
let
  caches = import ../../nix-caches.nix;
in
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
  users.users.root.openssh.authorizedKeys.keys = host.sshPublicKeys or [ ];
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = host.sshPublicKeys or [ ];
  };

  # Automatic updates are DISABLED: `system.autoUpgrade.flags = ["--flake" ".#<host>"]`
  # resolves relative to the host's working directory, but the flake source only
  # exists on the development Mac, so nixos-upgrade failed nightly with
  # "could not find a flake.nix". If unattended upgrades are ever wanted again,
  # point `system.autoUpgrade.flake` at a real flake source (e.g. a git URL) that
  # the host can actually fetch. See docs/nixos.md.

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
    # Single source of truth: nix-caches.nix (also used by flake.nix `nixConfig`
    # and modules/home/default.nix).
    extra-substituters = caches.extra-substituters;
    extra-trusted-public-keys = caches.extra-trusted-public-keys;
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
  services.journald.settings.Journal = {
    Storage = "persistent";
    MaxRetentionSec = "1month";
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
  # Wheel users don't need a password for sudo (single-user machine)
  security.sudo.wheelNeedsPassword = false;
}
