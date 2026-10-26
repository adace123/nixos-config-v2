{ config, ... }:
# Gatus: endpoint monitoring on dathomir, published tailnet-only as
# status.figtreelab.dev via the shared Caddy.
#
# Config is fully declarative — monitors, alerting and UI settings all live in
# `services.gatus.settings` below (rendered to YAML in the store), so a rebuild
# never loses a check. Only derived history (uptime results, events) lands on
# disk, in SQLite at /var/lib/gatus; see gatus-restic.nix for its backup.
#
# Secrets never go in `settings` (world-readable store path). Notification
# tokens interpolate via ${VAR} from the sops-rendered env file instead.
{
  services.gatus = {
    enable = true;
    environmentFile = config.sops.templates."gatus.env".path;
    settings = {
      web = {
        address = "127.0.0.1";
        port = 8088;
      };
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/gatus.db";
        caching = true;
      };
      ui = {
        header = "figtreelab";
        description = "Endpoint monitoring for the figtreelab tailnet";
      };
      # Hosted ntfy.sh: the notifier must survive dathomir dying, so it lives
      # off-box. Topic is the password (unguessable, in sops); no access token
      # — the topic alone gates a hosted reserved topic poorly, but the payload
      # is up/down + hostname, and ntfy.sh rate-limits publishers.
      alerting.ntfy = {
        topic = "\${NTFY_TOPIC}";
        priority = 4;
        default-alert = {
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };
      endpoints = [
        {
          name = "home-assistant";
          group = "coruscant";
          url = "https://ha.figtreelab.dev/";
          interval = "60s";
          client.timeout = "10s";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 5000"
          ];
          alerts = [ { type = "ntfy"; } ];
        }
        {
          name = "coruscant-https";
          group = "coruscant";
          url = "tcp://100.66.226.84:443";
          interval = "60s";
          conditions = [
            "[CONNECTED] == true"
          ];
          alerts = [ { type = "ntfy"; } ];
        }
        {
          name = "beszel-hub";
          url = "http://127.0.0.1:8090/";
          interval = "60s";
          conditions = [
            "[STATUS] == 200"
          ];
          alerts = [ { type = "ntfy"; } ];
        }
        {
          name = "pocket-id";
          url = "http://127.0.0.1:1411/healthz";
          interval = "60s";
          conditions = [
            # Backend answers 204 No Content (healthz_controller.go), not 200.
            "[STATUS] == 204"
          ];
          alerts = [ { type = "ntfy"; } ];
        }
        {
          name = "status-cert";
          url = "tls://status.figtreelab.dev:443";
          interval = "30m";
          client.timeout = "10s";
          conditions = [
            "[CONNECTED] == true"
            "[CERTIFICATE_EXPIRATION] > 720h"
          ];
          alerts = [ { type = "ntfy"; } ];
        }
        {
          name = "monitoring-cert";
          url = "tls://monitoring.figtreelab.dev:443";
          interval = "30m";
          client.timeout = "10s";
          conditions = [
            "[CONNECTED] == true"
            "[CERTIFICATE_EXPIRATION] > 720h"
          ];
          alerts = [ { type = "ntfy"; } ];
        }
      ];
    };
  };
  # systemd StateDirectory gives /var/lib/gatus to the DynamicUser unit, so the
  # sqlite path above always exists. The module sets StateDirectory already;
  # this only ensures the DB survives service restarts (it does — state dir,
  # not RuntimeDir) and names the backup source for gatus-restic.nix.
  # Topic is the password for the hosted ntfy.sh topic: unguessable, sops-held,
  # interpolated here rather than in `settings` (world-readable store path).
  sops.templates."gatus.env" = {
    content = ''
      NTFY_TOPIC=${config.sops.placeholder.ntfy-topic}
    '';
    mode = "0400";
  };
}
