{
  config,
  pkgs,
  ...
}:
let
  hassDir = "/var/lib/hass";
in
{
  services.home-assistant = {
    enable = true;
    package = pkgs.home-assistant.override {
      extraComponents = [
        "esphome"
        "met"
        "radio_browser"
        "systemmonitor"
        "bthome"
        "nextcloud"
        "unifi_direct"
        "unifi"
        "openweathermap"
        "tasmota"
        "icloud"
        "mqtt"
        "zwave_js"
        "zha"
        "bluetooth"
        "homekit"
        "wake_on_lan"
        "calendar"
        "weather"
        "todo"
        "assist_pipeline"
        "intent"
        "intent_script"
        "alert"
        "panel_custom"
        "hassio"
        "energy"
        "cloud"
      ];
      extraPackages = _: [ ];
    };
    customComponents = [ ];
    configWritable = true;
    openFirewall = true;
    config = {
      default_config = { };
      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "10.0.0.0/8"
          "172.16.0.0/12"
          "192.168.0.0/16"
        ];
      };
      logger = {
        default = "info";
        logs = {
          "homeassistant" = "info";
          "homeassistant.components" = "warning";
        };
      };
      recorder = {
        purge_keep_days = 10;
        db_url = "sqlite:///${hassDir}/home-assistant_v2.db";
      };
      history = { };
      logbook = { };
      sun = { };
      system_health = { };
      frontend = { };
      config = { };
      mobile_app = { };
      discovery = { };
      zeroconf = { };
      homeassistant = {
        name = "Coruscant";
        latitude = 0.0;
        longitude = 0.0;
        elevation = 0;
        unit_system = "metric";
        time_zone = config.time.timeZone;
        external_url = "http://coruscant.local:8123";
        internal_url = "http://coruscant.local:8123";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d ${hassDir} 0755 hass hass - -"
    "f ${hassDir}/automations.yaml 0644 hass hass - -"
    "f ${hassDir}/scenes.yaml 0644 hass hass - -"
    "f ${hassDir}/scripts.yaml 0644 hass hass - -"
    "f ${hassDir}/configuration.yaml 0644 hass hass - -"
  ];

  users.users.hass = {
    isSystemUser = true;
    description = "Home Assistant user";
    extraGroups = [
      "dialout"
      "gpio"
      "i2c"
    ];
    home = hassDir;
    shell = pkgs.bash;
  };

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

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant = {
        enabled = true;
      };
      permit_join = true;
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://localhost:1883";
      };
      serial = {
        port = "/dev/ttyUSB0";
        adapter = "ezsp";
      };
      frontend = {
        port = 8091;
      };
    };
  };

  services.esphome = {
    enable = true;
    openFirewall = true;
  };
}
