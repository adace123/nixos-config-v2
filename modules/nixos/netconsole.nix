{
  config,
  lib,
  ...
}:
let
  cfg = config.my.netconsoleSpec;
in
{
  options.my.netconsoleSpec = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "6666@192.168.4.53/end0,6666@192.168.4.20/aa:bb:cc:dd:ee:ff";
    description = ''
      Value for the kernel `netconsole=` parameter: a UDP sink for kernel messages
      that keeps working when the storage path and journald do not — which is why
      this host's failures have been invisible every time.

      Needs a machine on the same LAN listening for it (`nc -u -l 6666` on the
      workstation) and that machine's MAC address, because the kernel sends before
      ARP works: `arp -an | grep 192.168.4.20`. This console works before the clock,
      TLS, Tailscale or journald exist, so it is the one channel that cannot be
      taken down by the failure it is meant to report.

      Off by default: a GPIO UART is the durable alternative (pins 6/8/10 at
      115200 — see docs/nixos.md).
    '';
  };

  config.boot.kernelParams = lib.optional (cfg != null) "netconsole=${cfg}";
}
