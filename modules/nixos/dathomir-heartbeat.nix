{
  config,
  pkgs,
  ...
}:
# Dead-man's switch for dathomir itself. Gatus, the hub, and all probes live on
# this box, so a dead dathomir fires nothing — this timer pings a hosted
# Healthchecks.io check every 10 minutes, and the *absence* of pings (past the
# check's grace) is what pages. Delivery rides Healthchecks.io's own ntfy
# integration, off-box by design.
#
# The ping URL is a capability secret: sops-held, interpolated through a
# template, never literal here. If Gatus is down but the box is up, ping /fail
# so the check goes red immediately instead of waiting out the grace.
{
  systemd.services.dathomir-heartbeat = {
    description = "Ping the Healthchecks.io dead-man's switch";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = with pkgs; [
      curl
      systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      EnvironmentFile = config.sops.templates.healthchecks-ping-env.path;
    };
    script = ''
      set -euo pipefail
      if systemctl is-active --quiet gatus.service; then
        curl --max-time 15 -fsS "$HC_PING_URL" >/dev/null
      else
        curl --max-time 15 -fsS "$HC_PING_URL/fail" >/dev/null
      fi
    '';
  };

  sops.templates."healthchecks-ping-env" = {
    content = ''
      HC_PING_URL=${config.sops.placeholder.healthchecks-ping-url}
    '';
    mode = "0400";
  };

  systemd.timers.dathomir-heartbeat = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "10m";
      RandomizedDelaySec = "1m";
      Unit = "dathomir-heartbeat.service";
    };
  };
}
