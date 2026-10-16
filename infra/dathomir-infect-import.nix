# Module injected into the channel-based NixOS config that `nixos-infect`
# generates on the fresh dathomir instance.
#
# NOT imported by the flake. `scripts/dathomir-convert.sh` copies this file to
# `/etc/nixos/dathomir-import.nix` on the instance and runs nixos-infect with
# `NIXOS_IMPORT=./dathomir-import.nix`, so the generated configuration.nix
# imports it. The generated `hardware-configuration.nix` keeps owning the
# filesystems and bootloader (it reads them off the platform image's existing
# layout), and this module only has to bring the box back up reachable over SSH
# and Tailscale so the flake configuration can be activated over the tailnet.
#
# Keep this file free of flake inputs: it is evaluated against the NixOS channel
# nixos-infect installs, not against the flake's pinned nixpkgs.
_: {
  # The instance has no public IP and OCI's console is the only other way in, so
  # Tailscale is what makes the box accessible after the pivot.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    # Written by scripts/dathomir-convert.sh before the pivot, from the key
    # cloud-init already placed at /var/lib/tailscale/authkey. NIXOS_LUSTRATE
    # carries /etc/nixos across the pivot and drops /var, which is exactly why
    # this path is used instead of the cloud-init one.
    authKeyFile = "/etc/nixos/tailscale-authkey";
    extraUpFlags = [ "--ssh" ];
  };

  # Tailscale derives the node name from the hostname; pin it so MagicDNS keeps
  # resolving `dathomir` (the generated config takes it from `hostname -s`,
  # which on OCI is not guaranteed to be the instance's display name).
  networking.hostName = "dathomir";

  # nixos-infect leaves root owning the keys of the user it ran as (ubuntu).
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  # Needed for the `nixos-rebuild --flake github:...#dathomir` convergence step.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
