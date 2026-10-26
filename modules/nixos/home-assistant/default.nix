{
  config,
  lib,
  pkgs,
  ...
}:
let
  hassDir = "/var/lib/hass";
  # Hardcoded USB by-id path: swapping the dongle (or a different port) breaks
  # this. Prefer a stable udev symlink and update here if the dongle is replaced.
  zigbeeDongle = "/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_9aff399ca0f3ef1187f6bb1b6d9880ab-if00-port0";
  hacs = pkgs.fetchzip {
    url = "https://github.com/hacs/integration/releases/download/2.0.5/hacs.zip";
    hash = "sha256-iMomioxH7Iydy+bzJDbZxt6BX31UkCvqhXrxYFQV8Gw=";
    stripRoot = false;
  };
  # OpenID Connect login (Pocket ID) via hass-oidc-auth. The zip ships the
  # component files at its root, so stripRoot stays off and the store path
  # itself is copied to custom_components/auth_oidc below — same shape as
  # the hacs fetchzip above. The hash is the NAR of the *unpacked* tree
  # (fetchzip is recursive), not the zip file: GitHub's published asset
  # digest e5badaaa…47ccd is the flat file hash and will never verify here.
  authOidc = pkgs.fetchzip {
    url = "https://github.com/christiaangoossens/hass-oidc-auth/releases/download/v1.2.1/hass-oidc-auth.zip";
    hash = "sha256-zrOc7cRcME7v7dy4d+6kSyALdyKx+3LjetOc/cauN1c=";
    stripRoot = false;
  };
  hassGenerated = pkgs.runCommand "hass-generated-config" { } ''
    mkdir -p $out/automations $out/scripts $out/scenes $out/car_scripts $out/dashboards $out/custom_components
    cp ${./automations/system-monitor-alerts.yaml} $out/automations/system-monitor-alerts.yaml
    cp ${./automations/front-door-light-motion.yaml} $out/automations/front-door-light-motion.yaml
    cp ${./automations/front-door-record.yaml} $out/automations/front-door-record.yaml
    cp ${./automations/front-door-purge.yaml} $out/automations/front-door-purge.yaml
    cp ${./automations/car-maintenance.yaml} $out/automations/car-maintenance.yaml
    cp ${./automations/hyundai-alerts.yaml} $out/automations/hyundai-alerts.yaml
    cp ${./automations/charge-6-battery.yaml} $out/automations/charge-6-battery.yaml
    cp ${./automations/workout-complete-notification.yaml} $out/automations/workout-complete-notification.yaml
    cp ${./automations/home-assistant-issue-alert.yaml} $out/automations/home-assistant-issue-alert.yaml
    cp ${./scripts/car-maintenance.yaml} $out/scripts/car-maintenance.yaml
    cp ${./dashboards/system.yaml} $out/dashboards/system.yaml
    install -m0755 ${./car_scripts/car_rate.py} $out/car_scripts/car_rate.py
    cp -r ${./custom_components/google_health_workouts} $out/custom_components/google_health_workouts
  '';
in
{
  imports = [
    ./restic.nix
    ./ring-mqtt.nix
  ];

  sops.templates."hass-configuration.yaml" = {
    content =
      builtins.replaceStrings
        [
          "__TIME_ZONE__"
          "__EXTERNAL_DOMAIN__"
          "__ALEXA_NOTIFY_ME_API_KEY__"
          "__OIDC_CLIENT_ID__"
          "__OIDC_DISCOVERY_URL__"
        ]
        [
          config.time.timeZone
          config.sops.placeholder.home-assistant-external-domain
          config.sops.placeholder.alexa-notify-me-api-key
          config.sops.placeholder.oidc-client-id
          config.sops.placeholder.oidc-discovery-url
        ]
        (builtins.readFile ./configuration.yaml);
  };
  virtualisation = {
    oci-containers = {
      backend = "podman";
      containers.home-assistant = {
        image = "ghcr.io/home-assistant/home-assistant:latest";
        autoStart = true;
        volumes = [
          "${hassDir}:/config"
          "/etc/localtime:/etc/localtime:ro"
          "/run/dbus:/run/dbus:ro"
          "/media:/media"
        ];
        pull = "newer";
        labels = {
          "io.containers.autoupdate" = "registry";
        };
        environment.TZ = config.time.timeZone;
        extraOptions = [
          "--network=host"
          "--group-add=dialout"
          "--cap-add=NET_ADMIN"
          "--cap-add=NET_RAW"
        ];
      };
    };
  };

  systemd.services."podman-home-assistant" = {
    after = [ "mosquitto.service" ];
    requires = [ "mosquitto.service" ];
    serviceConfig = {
      # `always`, not `on-failure`: podman auto-update replaces the container by
      # stopping the unit, and if that is interrupted (it was, three times on
      # 2026-10-23 when the timer fired during the boot clock step) the unit was left
      # `failed` with nothing to bring it back. `always` restarts it from any exit;
      # an explicit `systemctl stop` is still honoured.
      Restart = lib.mkForce "always";
      RestartSec = "30s";
    };
  };

  # Auto-update keeps the container on the stable channel (ghcr's `latest` tracks
  # stable releases), which is what we want on a home-automation server — but the
  # timer must never fire during the boot clock step. The Pi has no RTC, so it boots
  # months in the past and chrony then steps the clock forward; every missed
  # OnCalendar timer elapses at once, and `podman auto-update` stopped Home Assistant
  # three times that way (2026-10-23). Two guards:
  #
  #   - the timer is ordered after time-sync.target, so it is not even armed until
  #     the clock is real (and if the network never syncs, it never runs);
  #   - Persistent = false, so a missed window is skipped rather than caught up at
  #     boot.
  #
  # A fixed weekly window plus a randomized delay keeps it clear of the restic jobs.
  systemd.services."podman-auto-update" = {
    wants = [
      "network-online.target"
      "time-sync.target"
    ];
    after = [
      "network-online.target"
      "time-sync.target"
      "nix-gc.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
      ExecStartPost = "${pkgs.podman}/bin/podman image prune -f";
    };
  };

  systemd.timers."podman-auto-update" = {
    wantedBy = [ "timers.target" ];
    wants = [ "time-sync.target" ];
    after = [ "time-sync.target" ];
    timerConfig = {
      OnCalendar = "Sun 04:00";
      Persistent = false;
      RandomizedDelaySec = "30m";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${hassDir}/automations 0755 hass hass -"
    "d ${hassDir}/car_scripts 0755 hass hass -"
    "d ${hassDir}/scripts 0755 hass hass -"
    "d ${hassDir}/scenes 0755 hass hass -"
    "d ${hassDir}/dashboards 0755 hass hass -"
    "d ${hassDir}/.storage 0755 hass hass -"
    "d ${hassDir}/backups 0755 hass hass -"
    "d ${hassDir}/logs 0755 hass hass -"
    "d ${hassDir}/www 0755 hass hass -"
    "d ${hassDir}/custom_components 0755 hass hass -"
    "d /media 0755 hass hass -"
    "d /media/doorbell 0755 hass hass -"
  ];

  system.activationScripts.home-assistant-config = {
    text = ''
      mkdir -p ${hassDir}
      rm -rf ${hassDir}/automations
      mkdir -p ${hassDir}/automations
      cp -r ${hassGenerated}/automations/. ${hassDir}/automations/
      rm -rf ${hassDir}/scripts
      mkdir -p ${hassDir}/scripts
      cp -r ${hassGenerated}/scripts/. ${hassDir}/scripts/
      rm -rf ${hassDir}/scenes
      mkdir -p ${hassDir}/scenes
      cp -r ${hassGenerated}/scenes/. ${hassDir}/scenes/
      rm -rf ${hassDir}/dashboards
      mkdir -p ${hassDir}/dashboards
      cp -r ${hassGenerated}/dashboards/. ${hassDir}/dashboards/
      chown -R hass:hass ${hassDir}/dashboards
      install -m0755 ${hassGenerated}/car_scripts/car_rate.py ${hassDir}/car_scripts/car_rate.py
      chown hass:hass ${hassDir}/car_scripts/car_rate.py
      if [ ! -e ${hassDir}/automations.yaml ]; then
        printf '[]\n' > ${hassDir}/automations.yaml
      fi
      chown hass:hass ${hassDir}/automations.yaml
      chmod 0644 ${hassDir}/automations.yaml
      ${pkgs.coreutils}/bin/install -Dm644 ${
        config.sops.templates."hass-configuration.yaml".path
      } ${hassDir}/configuration.yaml
      mkdir -p ${hassDir}/.storage ${hassDir}/backups ${hassDir}/logs ${hassDir}/www ${hassDir}/custom_components
      ${pkgs.findutils}/bin/find ${hassDir}/custom_components -maxdepth 1 -type f -delete
      rm -rf ${hassDir}/custom_components/hacs ${hassDir}/custom_components/hacs_frontend ${hassDir}/custom_components/__pycache__
      cp -r ${hacs} ${hassDir}/custom_components/hacs
      rm -rf ${hassDir}/custom_components/auth_oidc
      cp -r ${authOidc} ${hassDir}/custom_components/auth_oidc
      chown -R hass:hass ${hassDir}/custom_components/auth_oidc
      rm -rf ${hassDir}/custom_components/google_health_workouts
      cp -r ${hassGenerated}/custom_components/google_health_workouts ${hassDir}/custom_components/google_health_workouts
      chown -R hass:hass ${hassDir}/custom_components/google_health_workouts
    '';
    deps = [
      "users"
      "setupSecrets"
    ];
  };

  networking.firewall.allowedTCPPorts = [ 8123 ];
  # TP-Link Kasa/Tapo discovery (python-kasa): broadcasts go out on UDP 9999/20002,
  # but devices reply to the source's ephemeral port (modern python-kasa binds a
  # random port, and broadcast replies aren't matched by conntrack ESTABLISHED).
  # Open both the discovery port and the Linux ephemeral range inbound.
  networking.firewall.allowedUDPPorts = [ 9999 ];
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 32768;
      to = 60999;
    }
  ];

  users.users.hass = {
    isSystemUser = true;
    description = "Home Assistant user";
    group = "hass";
    extraGroups = [
      "dialout"
      "gpio"
      "i2c"
    ];
    home = hassDir;
    shell = pkgs.bash;
  };

  users.groups.hass = { };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        address = "127.0.0.1";
        acl = [
          "topic readwrite #"
          "pattern readwrite #"
        ];
        omitPasswordAuth = true;
        settings = {
          allow_anonymous = true;
          max_connections = -1;
          protocol = "mqtt";
        };
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      permit_join = false;
      mqtt = {
        base_topic = "zigbee2mqtt";
        # 127.0.0.1, not `localhost`: on these hosts `localhost` resolves to ::1
        # only, and mosquitto listens on `listener 1883 127.0.0.1`, so
        # `mqtt://localhost:1883` fails with `ECONNREFUSED ::1:1883` whenever the
        # resolver picks IPv6 — which is how the coordinator came up dead on boot
        # with the unit reported active (coruscant, 2026-10-23).
        server = "mqtt://127.0.0.1:1883";
      };
      serial = {
        port = zigbeeDongle;
        adapter = "ember";
      };
      frontend.port = 8091;
    };
  };

  # Keep the coordinator alive across boots. The nixpkgs module hardens this unit
  # with `DevicePolicy = "closed"` plus `DeviceAllow = <the by-id path>`, and
  # systemd resolves that path when it *loads* the unit — which at boot happens
  # before udev has published /dev/serial/by-id/. The closed policy then denies
  # the port with EPERM for the rest of the boot, but zigbee2mqtt stays alive in
  # that broken state, so `Restart = on-failure` never fires and the Zigbee
  # network is silently dead while systemd still reports the unit `active`
  # (coruscant, 2026-10-23: `Failed to init port: Operation not permitted`,
  # HOST_FATAL_ERROR, nothing on 8091; a manual restart fixed it). Opening the
  # device cgroup avoids the race entirely; the module's other sandboxing
  # (PrivateUsers, ProtectSystem=strict, syscall filter) is untouched.
  systemd.services.zigbee2mqtt = {
    # The module only orders this after network.target, but zigbee2mqtt exits
    # rather than retrying when MQTT is unreachable ("MQTT failed to connect,
    # exiting"). At boot mosquitto comes up a second or two later, so the
    # coordinator died on every boot while the unit stayed put in a broken
    # state (coruscant, 2026-10-23).
    after = [ "mosquitto.service" ];
    requires = [ "mosquitto.service" ];
    serviceConfig = {
      DevicePolicy = lib.mkForce "auto";
      DeviceAllow = lib.mkForce [ ];
    };
  };

  # Disabled: upstream ESPHome removed the built-in dashboard, but nixpkgs'
  # module still execs `esphome dashboard`, so the unit exits 1 every ~2s and
  # systemd restarts it forever (the restart counter reached 250 on coruscant's
  # last boot — pure process churn for a service that cannot start). Run ESPHome
  # Device Builder (as a podman container beside HA) if the UI is wanted again.
  services.esphome = {
    enable = false;
  };

  environment.systemPackages = with pkgs; [
    nmap
    iputils
    net-tools
    usbutils
    lsof
    bluez
    bluez-tools
    i2c-tools
    wiringpi
  ];
}
