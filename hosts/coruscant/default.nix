{
  hostName = "coruscant";
  system = "aarch64-linux";
  sshPublicKeys = import ../rpi-keys.nix;
  # Reports to the beszel hub on dathomir, authenticating with the universal
  # `beszel-token` and the hub SSH public key `beszel-key` in
  # secrets/coruscant.yaml.
  beszelAgent = true;
  # Advertise the home LAN as a Tailscale subnet route (see
  # modules/nixos/common.nix): tailnet members can reach LAN devices that
  # do not run Tailscale, via coruscant. 192.168.4.0/24 is the eero LAN;
  # Home Assistant was polling a TP-Link device at 192.168.4.37 on it.
  tailscaleSubnetRoutes = [ "192.168.4.0/24" ];
}
