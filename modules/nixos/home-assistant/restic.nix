{ config, pkgs, ... }:
{
  sops.secrets = {
    cloudflare-access-key-id = {
      sopsFile = ../../../secrets/cloudflare.yaml;
    };
    cloudflare-bucket-name = {
      sopsFile = ../../../secrets/cloudflare.yaml;
    };
    cloudflare-endpoint = {
      sopsFile = ../../../secrets/cloudflare.yaml;
    };
    cloudflare-secret-access-key = {
      sopsFile = ../../../secrets/cloudflare.yaml;
    };
    restic-password = {
      sopsFile = ../../../secrets/cloudflare.yaml;
    };
  };

  sops.templates."restic-home-assistant.env" = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.cloudflare-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.cloudflare-secret-access-key}
      AWS_DEFAULT_REGION=auto
      RESTIC_REPOSITORY=s3:${config.sops.placeholder.cloudflare-endpoint}/${config.sops.placeholder.cloudflare-bucket-name}/coruscant
      RESTIC_PASSWORD_FILE=${config.sops.secrets.restic-password.path}
    '';
    mode = "0400";
  };

  systemd.services.home-assistant-restic-backup = {
    description = "Back up Home Assistant to Cloudflare R2 with Restic";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.restic
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = config.sops.templates."restic-home-assistant.env".path;
      CacheDirectory = "restic-home-assistant";
    };
    script = ''
      set -euo pipefail

      systemctl stop podman-home-assistant.service
      trap 'systemctl start podman-home-assistant.service' EXIT

      restic -o s3.bucket-lookup=path backup /var/lib/hass \
        --tag home-assistant \
        --exclude=/var/lib/hass/deps \
        --exclude=/var/lib/hass/logs \
        --exclude=/var/lib/hass/tts

      restic -o s3.bucket-lookup=path forget \
        --tag home-assistant \
        --keep-daily 14 \
        --keep-weekly 8 \
        --keep-monthly 6 \
        --prune
    '';
  };

  systemd.timers.home-assistant-restic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };

  systemd.services.home-assistant-restic-check = {
    description = "Verify the Home Assistant Restic repository";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.restic ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      EnvironmentFile = config.sops.templates."restic-home-assistant.env".path;
      CacheDirectory = "restic-home-assistant";
    };
    script = ''
      set -euo pipefail
      restic -o s3.bucket-lookup=path check
    '';
  };

  systemd.timers.home-assistant-restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 04:30:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
