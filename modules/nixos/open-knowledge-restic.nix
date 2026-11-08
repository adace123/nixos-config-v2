{
  config,
  pkgs,
  ...
}:
# Back the OpenKnowledge project up to Cloudflare R2, same pattern as
# gatus-restic.nix: same bucket (`dathomir` repository path), own tag.
#
# What is worth restoring is the whole state directory: the notes clone (with
# its history) and the server's own state under .ok/ — publish metadata, sync
# bookkeeping and the edit-history repo at .git/ok. Everything declarative
# (this unit, the Caddy vhost, the package) lives in Nix.
#
# Stopping the service gives a consistent git repository and a quiesced state
# dir; the trap restarts it even when the backup fails. Same outage class as
# the other two jobs, different window (04:15).
{
  sops.secrets = {
    cloudflare-access-key-id.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-bucket-name.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-endpoint.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-secret-access-key.sopsFile = ../../secrets/cloudflare.yaml;
    restic-password.sopsFile = ../../secrets/cloudflare.yaml;
  };

  sops.templates."restic-open-knowledge.env" = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.cloudflare-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.cloudflare-secret-access-key}
      AWS_DEFAULT_REGION=auto
      RESTIC_REPOSITORY=s3:${config.sops.placeholder.cloudflare-endpoint}/${config.sops.placeholder.cloudflare-bucket-name}/dathomir
      RESTIC_PASSWORD_FILE=${config.sops.secrets.restic-password.path}
    '';
    mode = "0400";
  };

  systemd.services.open-knowledge-restic-backup = {
    description = "Back up the OpenKnowledge project to Cloudflare R2 with Restic";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.restic
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = config.sops.templates."restic-open-knowledge.env".path;
      CacheDirectory = "restic-open-knowledge";
    };
    script = ''
      set -euo pipefail

      systemctl stop open-knowledge.service
      trap 'systemctl start open-knowledge.service' EXIT

      if ! restic -o s3.bucket-lookup=path cat config >/dev/null 2>&1; then
        restic -o s3.bucket-lookup=path init
      fi

      restic -o s3.bucket-lookup=path --retry-lock 10m backup /var/lib/open-knowledge \
        --tag open-knowledge

      restic -o s3.bucket-lookup=path --retry-lock 10m forget \
        --tag open-knowledge \
        --keep-daily 14 \
        --keep-weekly 8 \
        --keep-monthly 6 \
        --prune
    '';
  };

  systemd.timers.open-knowledge-restic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:15:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.open-knowledge-restic-check = {
    description = "Verify the OpenKnowledge project's Restic repository";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.restic ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."restic-open-knowledge.env".path;
      CacheDirectory = "restic-open-knowledge";
    };
    script = ''
      set -euo pipefail
      restic -o s3.bucket-lookup=path --retry-lock 20m check
    '';
  };

  systemd.timers.open-knowledge-restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 06:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
