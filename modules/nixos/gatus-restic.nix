{
  config,
  pkgs,
  ...
}:
# Back Gatus's SQLite history up to Cloudflare R2, same pattern as
# beszel-hub-restic.nix: same bucket (`dathomir` repository path), own tag.
#
# Only history lives here — monitors and alerting are declarative in
# gatus.nix, so a restore only recovers uptime graphs, not config.
# Gatus writes WAL-mode SQLite like the hub, so stop it for a consistent copy.
# Same ~2s outage class, different window (04:00).
{
  sops.secrets = {
    cloudflare-access-key-id.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-bucket-name.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-endpoint.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-secret-access-key.sopsFile = ../../secrets/cloudflare.yaml;
    restic-password.sopsFile = ../../secrets/cloudflare.yaml;
  };

  sops.templates."restic-gatus.env" = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.cloudflare-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.cloudflare-secret-access-key}
      AWS_DEFAULT_REGION=auto
      RESTIC_REPOSITORY=s3:${config.sops.placeholder.cloudflare-endpoint}/${config.sops.placeholder.cloudflare-bucket-name}/dathomir
      RESTIC_PASSWORD_FILE=${config.sops.secrets.restic-password.path}
    '';
    mode = "0400";
  };

  systemd.services.gatus-restic-backup = {
    description = "Back up Gatus history to Cloudflare R2 with Restic";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.restic
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = config.sops.templates."restic-gatus.env".path;
      CacheDirectory = "restic-gatus";
    };
    script = ''
      set -euo pipefail

      systemctl stop gatus.service
      trap 'systemctl start gatus.service' EXIT

      if ! restic -o s3.bucket-lookup=path cat config >/dev/null 2>&1; then
        restic -o s3.bucket-lookup=path init
      fi

      restic -o s3.bucket-lookup=path --retry-lock 10m backup /var/lib/gatus \
        --tag gatus

      restic -o s3.bucket-lookup=path --retry-lock 10m forget \
        --tag gatus \
        --keep-daily 14 \
        --keep-weekly 8 \
        --keep-monthly 6 \
        --prune
    '';
  };

  systemd.timers.gatus-restic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.gatus-restic-check = {
    description = "Verify the Gatus Restic repository";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.restic ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."restic-gatus.env".path;
      CacheDirectory = "restic-gatus";
    };
    script = ''
      set -euo pipefail
      restic -o s3.bucket-lookup=path --retry-lock 20m check
    '';
  };

  systemd.timers.gatus-restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:30:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
