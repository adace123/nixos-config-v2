{
  config,
  pkgs,
  ...
}:
let
  hassDir = "/var/lib/hass";

  configurationYaml = pkgs.writeText "configuration.yaml" ''
    default_config:

    automation ui: !include automations.yaml
    scene ui: !include scenes.yaml
    script ui: !include scripts.yaml

    http:
      server_host: "::"
      server_port: 8123
      use_x_forwarded_for: true
      trusted_proxies:
        - 127.0.0.1
        - ::1

    logger:
      default: info
      logs:
        homeassistant: info
        homeassistant.components: warning

    recorder:
      purge_keep_days: 10
      db_url: sqlite:///config/home-assistant_v2.db

    history:

    logbook:

    sun:

    system_health:

    frontend:

    config:

    mobile_app:

    discovery:

    zeroconf:

    homeassistant:
      name: Coruscant
      latitude: 0.0
      longitude: 0.0
      elevation: 0
      unit_system: metric
      time_zone: ${config.time.timeZone}
      external_url: http://coruscant.local:8123
      internal_url: http://coruscant.local:8123
  '';
in
{
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
        ];
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
  };

  systemd.tmpfiles.rules = [
    "d ${hassDir} 0755 hass hass - -"
    "f ${hassDir}/automations.yaml 0644 hass hass - -"
    "f ${hassDir}/scenes.yaml 0644 hass hass - -"
    "f ${hassDir}/scripts.yaml 0644 hass hass - -"
    "L+ ${hassDir}/configuration.yaml - - - - ${configurationYaml}"
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
        address = "0.0.0.0";
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
        adapter = "ezsp";
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
    zigbee2mqtt
  ];
}
