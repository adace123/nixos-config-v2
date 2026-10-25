{
  config,
  pkgs,
  ...
}:
# Back the beszel hub's PocketBase data up to Cloudflare R2, in the same bucket
# the Home Assistant snapshots use but under its own repository path.
#
# The hub holds state nothing else can rebuild: users, notification channels,
# alert rules and thresholds, history, and the ed25519 host keypair every agent
# verifies. None of it lives in git — the alert rules are UI objects — so before
# this module the VPS had no backup at all and losing the instance lost the whole
# monitoring setup with it.
#
# The hub is stopped for the copy: PocketBase keeps SQLite in WAL mode, and only a
# clean shutdown checkpoints the WAL into a consistent data.db. It is a ~2 second
# outage, scheduled away from the Home Assistant job on coruscant (03:30).
#
# Cost of this design: dathomir now holds the R2 credentials, which are scoped to
# the bucket rather than to a repository path, so a rooted VPS could delete the
# Home Assistant snapshots too. That is the price of not keeping the backup off
# the machine that needs restoring; the follow-up is a separate bucket and token
# for this repository, which is a Cloudflare-side change.
let
  cfg = config.services.beszel.hub;
  # DynamicUser + StateDirectory relocates the state dir under /var/lib/private;
  # dataDir itself is the symlink user-facing code sees. Back up the real path.
  stateDir = "${dirOf cfg.dataDir}/private/${baseNameOf cfg.dataDir}";
in
{
  sops.secrets = {
    cloudflare-access-key-id.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-bucket-name.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-endpoint.sopsFile = ../../secrets/cloudflare.yaml;
    cloudflare-secret-access-key.sopsFile = ../../secrets/cloudflare.yaml;
    restic-password.sopsFile = ../../secrets/cloudflare.yaml;
  };

  sops.templates."restic-beszel-hub.env" = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.cloudflare-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.cloudflare-secret-access-key}
      AWS_DEFAULT_REGION=auto
      RESTIC_REPOSITORY=s3:${config.sops.placeholder.cloudflare-endpoint}/${config.sops.placeholder.cloudflare-bucket-name}/dathomir
      RESTIC_PASSWORD_FILE=${config.sops.secrets.restic-password.path}
    '';
    mode = "0400";
  };

  systemd.services.beszel-hub-restic-backup = {
    description = "Back up the beszel hub to Cloudflare R2 with Restic";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.restic
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = config.sops.templates."restic-beszel-hub.env".path;
      CacheDirectory = "restic-beszel-hub";
    };
    script = ''
      set -euo pipefail

      systemctl stop beszel-hub.service
      # The hub must come back even when the backup fails; a trap does that
      # unconditionally, as the Home Assistant job does for podman.
      trap 'systemctl start beszel-hub.service' EXIT

      # A fresh bucket path has no repository yet, and restic refuses to back up
      # into one. Create it on first run so a rebuilt VPS does not stall on a
      # manual `restic init` — which is exactly what the first deploy hit
      # (dathomir, 2026-10-25: "Fatal: repository does not exist").
      if ! restic -o s3.bucket-lookup=path cat config >/dev/null 2>&1; then
        restic -o s3.bucket-lookup=path init
      fi

      # --retry-lock: the weekly check holds an exclusive lock, and a VPS without
      # an RTC can fire both at once after a clock step.
      restic -o s3.bucket-lookup=path --retry-lock 10m backup ${stateDir} \
        --tag beszel-hub

      restic -o s3.bucket-lookup=path --retry-lock 10m forget \
        --tag beszel-hub \
        --keep-daily 14 \
        --keep-weekly 8 \
        --keep-monthly 6 \
        --prune
    '';
  };

  systemd.timers.beszel-hub-restic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:45:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.beszel-hub-restic-check = {
    description = "Verify the beszel hub Restic repository";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.restic ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."restic-beszel-hub.env".path;
      CacheDirectory = "restic-beszel-hub";
    };
    script = ''
      set -euo pipefail
      restic -o s3.bucket-lookup=path --retry-lock 20m check
    '';
  };

  systemd.timers.beszel-hub-restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:00:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
