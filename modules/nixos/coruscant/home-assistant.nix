{
  config,
  pkgs,
  ...
}:
let
  hassDir = "/var/lib/hass";
in
{
  sops.templates."hass-configuration.yaml" = {
    content =
      builtins.replaceStrings
        [ "__TIME_ZONE__" "__EXTERNAL_URL__" ]
        [ config.time.timeZone config.sops.placeholder.home-assistant-external-domain ]
        (builtins.readFile ./configuration.yaml);
  };
  virtualisation = {
    podman.autoPrune = {
      enable = true;
      dates = "weekly";
    };
    oci-containers = {
      backend = "podman";
      containers.home-assistant = {
        image = "ghcr.io/home-assistant/home-assistant:stable";
        autoStart = true;
        volumes = [
          "${hassDir}:/config"
          "/etc/localtime:/etc/localtime:ro"
          "/run/dbus:/run/dbus:ro"
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
    after = [
      "mosquitto.service"
      "copy-hass-config.service"
    ];
    requires = [ "mosquitto.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  # Podman auto-update: containers with io.containers.autoupdate=registry
  # get their images pulled weekly and are restarted automatically.
  systemd.services."podman-auto-update" = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.podman}/bin/podman auto-update";
      ExecStartPost = "${pkgs.podman}/bin/podman image prune -f";
    };
  };

  systemd.timers."podman-auto-update" = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "weekly";
  };

  # Copy rendered HA config before HA starts.  Sops templates are guaranteed
  # to be rendered during activation, before any systemd service starts.
  systemd.services."copy-hass-config" = {
    description = "Copy rendered HA configuration";
    before = [ "podman-home-assistant.service" ];
    requiredBy = [ "podman-home-assistant.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      ${pkgs.coreutils}/bin/cp ${
        config.sops.templates."hass-configuration.yaml".path
      } ${hassDir}/configuration.yaml
      ${pkgs.coreutils}/bin/chown -R hass:hass ${hassDir}
    '';
  };

  system.activationScripts.home-assistant-config = {
    text = ''
      mkdir -p ${hassDir}
      touch ${hassDir}/automations.yaml ${hassDir}/scenes.yaml ${hassDir}/scripts.yaml
      ${pkgs.coreutils}/bin/chown -R hass:hass ${hassDir}
    '';
    deps = [ "users" ];
  };

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
        settings = {
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
      permit_join = true;
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://localhost:1883";
      };
      serial = {
        port = "/dev/ttyUSB0";
        adapter = "ember";
      };
      frontend.port = 8091;
    };
  };

  services.esphome = {
    enable = true;
    openFirewall = true;
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
