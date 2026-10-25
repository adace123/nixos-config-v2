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

  # Boot-time stampede control. The Pi hosts have no RTC, so they boot months in the
  # past and chrony then steps the clock forward; every missed OnCalendar timer
  # elapses at once. On 2026-10-23 that started nix-gc, fstrim, the restic backup and
  # its check, logrotate, podman-prune and podman auto-update within a second of each
  # other on a Pi 4 — and podman auto-update stopping Home Assistant is what took the
  # services down. Ordering the heavy oneshots after time-sync.target keeps them off
  # a bogus clock, and the `after` chains make systemd run them serially rather than
  # concurrently. `Persistent = true` is deliberately left alone on the timers: a
  # skipped backup is worse than a busy minute.
  systemd.services.logrotate = {
    wants = [ "time-sync.target" ];
    after = [ "time-sync.target" ];
  };
  systemd.services.nix-gc = {
    wants = [ "time-sync.target" ];
    after = [
      "time-sync.target"
      "logrotate.service"
    ];
  };

  # Nix settings for better performance
  nix.settings = {
    auto-optimise-store = true;
    max-jobs = 4;
    cores = 4;
    # Single source of truth: nix-caches.nix (also used by flake.nix `nixConfig`
    # and modules/home/default.nix).
    inherit (caches) extra-substituters;
    inherit (caches) extra-trusted-public-keys;
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

  # Keep the clock in step, and make it step hard at boot. The Pi hosts have no
  # RTC, so they come up on a bogus date until NTP corrects them; while the clock
  # is wrong every TLS handshake fails (certificates look not-yet-valid), which
  # takes Tailscale down with it and makes the host unreachable on the tailnet
  # even though its LAN is fine. ntpd only slews, so a freshly booted box could
  # sit unreachable for minutes; chrony steps the clock on its first few updates.
  # See .pi/plans/coruscant-unresponsive-diagnosis.md
  services.chrony = {
    enable = true;
    servers = [ "pool.ntp.org" ];
    extraConfig = "makestep 1.0 3";
  };

  # Enable log rotation
  services.logrotate.enable = true;

  # Configure journald for persistent logging
  services.journald.settings.Journal = {
    Storage = "persistent";
    MaxRetentionSec = "1month";
    # Retention alone does not bound size when one host is chatty:
    # coruscant's journal reached 2.1G in Oct 2026, mostly Home
    # Assistant container stdout. Cap total size and keep breathing
    # room on the root filesystem.
    SystemMaxUse = "512M";
    SystemKeepFree = "1G";
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
