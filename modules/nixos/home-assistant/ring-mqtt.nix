{
  host,
  lib,
  ...
}:
let
  ringDataDir = "/var/lib/ring-mqtt";
  # docker.io, not ghcr.io: ghcr denies anonymous token issuance for this
  # repo (403 on the token endpoint from every network we tried), while the
  # publisher's own Docker Hub mirror serves the same tags. Verified
  # multi-arch incl. arm64; the Pi pulls it clean.
  ringImage = "docker.io/tsightler/ring-mqtt:5.9.3";
in
{
  # Only coruscant has the doorbell: base.nix is shared with threepio, which
  # must not pull the image or publish the ports.
  config = lib.mkIf (host.hostName == "coruscant") {
    # Ring → MQTT bridge (podman container, like Home Assistant: no nixpkgs
    # package exists). Publishes ding/motion/snapshot entities via the existing
    # Mosquitto broker (MQTT discovery, no HA config needed) and serves the
    # doorbell as local RTSP at 127.0.0.1:8554/<ring-id>_live.
    #
    # Viewing needs no new service: HA 2026.10's embedded go2rtc (already
    # running inside the HA container, per default_config) WebRTC-proxies any
    # RTSP camera source — a standalone go2rtc module would only duplicate
    # that stack for extra RAM and a second copy of the RTSP password.
    #
    # RTSP has no auth (no livestream_user/pass): the port is loopback-published
    # only, same posture as the anonymous loopback-only Mosquitto. HA runs
    # --network=host so it reaches 127.0.0.1:8554 directly.
    #
    # Disk/RAM posture: idle-light bridge (~150 MB RSS), writes are two small
    # JSON files; RTSP only spins up on demand, never continuous (a battery
    # doorbell sleeps between events, and Ring suppresses motion/ding alerts
    # while a live stream is active).
    #
    # First boot needs a Ring refresh token: with no ring_token in the state
    # file the container serves a one-time auth UI on 127.0.0.1:55123 (Ring
    # credentials + 2FA), which stops itself once connected. Reach it over
    # `ssh -L 55123:127.0.0.1:55123 root@coruscant.local`. The token persists
    # in ring-state.json — the only non-reproducible bit, so it rides the R2
    # backup job via the tag below.
    #
    # Endgame for the official `ring` integration (double-client API polling
    # risks throttling): keep it until ring-mqtt's MQTT entities + an RTSP
    # generic-camera cover ding/motion/live-view, then delete that config entry.
    virtualisation.oci-containers.containers.ring-mqtt = {
      image = ringImage;
      pull = "newer";
      labels = {
        "io.containers.autoupdate" = "registry";
      };
      volumes = [
        "${ringDataDir}:/data"
      ];
      environment = {
        DEBUG = "ring-mqtt";
      };
      extraOptions = [
        "--publish=127.0.0.1:8554:8554/tcp"
        "--publish=127.0.0.1:55123:55123/tcp"
      ];
    };

    sops.templates."ring-mqtt-config.json" = {
      # Rendered straight into the state dir (sops templates re-render on every
      # activation, so editing the JSON below redeploys without touching state).
      path = "${ringDataDir}/config.json";
      mode = "0400";
      content = builtins.toJSON {
        # 127.0.0.1, not `localhost`: on these hosts `localhost` resolves to
        # ::1 only and mosquitto listens on 127.0.0.1 — same trap zigbee2mqtt
        # hit (see the comment on its mqtt.server setting).
        mqtt_url = "mqtt://127.0.0.1:1883";
        mqtt_options = "";
        livestream_user = "";
        livestream_pass = "";
        disarm_code = "";
        enable_cameras = true;
        enable_modes = false;
        enable_panic = false;
        hass_topic = "homeassistant/status";
        ring_topic = "ring";
        location_ids = [ ];
      };
    };

    # ring-mqtt exits instead of retrying when MQTT is unreachable (same shape
    # as the zigbee2mqtt boot race), so order it behind the broker. The podman
    # backend generates podman-ring-mqtt.service from the container above.
    systemd.services."podman-ring-mqtt" = {
      after = [ "mosquitto.service" ];
      requires = [ "mosquitto.service" ];
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = "30s";
      };
    };

    # State dir holds config.json (above) + ring-state.json (the refresh token).
    # tmpfiles only ensures the dir exists; the template owns config.json.
    systemd.tmpfiles.rules = [
      "d ${ringDataDir} 0755 root root -"
    ];

    # The HA backup job stops only HA; ring-mqtt keeps running and its two tiny
    # JSON files are consistent enough to snapshot live — but they live outside
    # /var/lib/hass, so include them in the same R2 repository under own tag.
    systemd.services.home-assistant-restic-backup.script = lib.mkAfter ''
      restic -o s3.bucket-lookup=path --retry-lock 5m backup ${ringDataDir} \
        --tag ring-mqtt
    '';
  };
}
