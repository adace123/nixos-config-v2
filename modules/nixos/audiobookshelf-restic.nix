{
  config,
  pkgs,
  ...
}:
# Back Audiobookshelf up to Cloudflare R2, same pattern as
# gatus-restic.nix / open-knowledge-restic.nix: same bucket (`dathomir`
# repository path), own tag.
#
# What is worth restoring is everything in the state directory: the SQLite
# database (users, libraries, progress), metadata, and the MP3s under
# podcasts/ and audiobooks/. Everything declarative (this unit, the Caddy
# vhost, the service itself) lives in Nix.
#
# Two snapshots per run, because only part of that needs quiescing:
#
#   - config/ and metadata/ hold the SQLite database and its index. The
#     service is stopped for exactly this copy — seconds, like the other
#     jobs — and the trap restarts it even when the backup fails.
#   - The media directories are append-only between uploads, so they are
#     copied with the service running. Stopping it for the whole upload
#     would take the podcast server offline for as long as new episodes
#     take to reach R2.
#
# Both snapshots carry the `audiobookshelf` tag so one retention policy
# covers them; restore needs both. The repository grows with the library —
# if it ever gets large, revisit whether media belongs in the backup or only
# the database does.
{
  sops.secrets = {
    cloudflare-access-key-id.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-bucket-name.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-endpoint.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-secret-access-key.sopsFile = ../../secrets/cloudflare.yaml;
    restic-password.sopsFile = ../../secrets/cloudflare.yaml;
  };

  sops.templates."restic-audiobookshelf.env" = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.cloudflare-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.cloudflare-secret-access-key}
      AWS_DEFAULT_REGION=auto
      RESTIC_REPOSITORY=s3:${config.sops.placeholder.cloudflare-endpoint}/${config.sops.placeholder.cloudflare-bucket-name}/dathomir
      RESTIC_PASSWORD_FILE=${config.sops.secrets.restic-password.path}
    '';
    mode = "0400";
  };

  systemd.services.audiobookshelf-restic-backup = {
    description = "Back up Audiobookshelf to Cloudflare R2 with Restic";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.restic
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = config.sops.templates."restic-audiobookshelf.env".path;
      CacheDirectory = "restic-audiobookshelf";
    };
    script = ''
      set -euo pipefail

      systemctl stop audiobookshelf.service
      trap 'systemctl start audiobookshelf.service' EXIT

      if ! restic -o s3.bucket-lookup=path cat config >/dev/null 2>&1; then
        restic -o s3.bucket-lookup=path init
      fi

      e=0
      # Database and metadata: the only part that needs a stopped service.
      restic -o s3.bucket-lookup=path --retry-lock 10m backup \
        /var/lib/audiobookshelf/config \
        /var/lib/audiobookshelf/metadata \
        --tag audiobookshelf || e=$?

      # Back up whether or not the first pass succeeded, and don't leave the
      # server down: an upload fault must not cost the media copy or the site.
      systemctl start audiobookshelf.service
      trap - EXIT

      # Media: append-only between uploads, so the service stays up.
      restic -o s3.bucket-lookup=path --retry-lock 10m backup \
        /var/lib/audiobookshelf/podcasts \
        /var/lib/audiobookshelf/audiobooks \
        --tag audiobookshelf || e=$?

      restic -o s3.bucket-lookup=path --retry-lock 10m forget \
        --tag audiobookshelf \
        --keep-daily 14 \
        --keep-weekly 8 \
        --keep-monthly 6 \
        --prune

      exit "$e"
    '';
  };

  systemd.timers.audiobookshelf-restic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.audiobookshelf-restic-check = {
    description = "Verify the Audiobookshelf Restic repository";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.restic ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."restic-audiobookshelf.env".path;
      CacheDirectory = "restic-audiobookshelf";
    };
    script = ''
      set -euo pipefail
      restic -o s3.bucket-lookup=path --retry-lock 20m check
    '';
  };

  systemd.timers.audiobookshelf-restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 06:30:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
