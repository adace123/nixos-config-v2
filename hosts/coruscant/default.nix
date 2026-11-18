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
  # do not run Tailscale, via coruscant. The eero LAN is 192.168.4.0/22
  # (255.255.252.0, broadcast 192.168.7.255 — coruscant's own end0 is
  # 192.168.4.53/22), not a /24: the eero nodes sit at 192.168.6.51/.52
  # and DHCP also hands out addresses there. Home Assistant was polling a
  # TP-Link device at 192.168.4.37 on it.
  tailscaleSubnetRoutes = [ "192.168.4.0/22" ];
}
