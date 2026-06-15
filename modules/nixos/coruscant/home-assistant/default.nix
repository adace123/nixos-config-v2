{
  config,
  pkgs,
  ...
}:
let
  hassDir = "/var/lib/hass";
  zigbeeDongle = "/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_9aff399ca0f3ef1187f6bb1b6d9880ab-if00-port0";
  hassGenerated = pkgs.runCommand "hass-generated-config" { } ''
    mkdir -p $out/automations $out/scripts $out/scenes
    cp ${./automations/washer.yaml} $out/automations/washer.yaml
  '';
in
{
  sops.templates."hass-configuration.yaml" = {
    content =
      builtins.replaceStrings
        [ "__TIME_ZONE__" "__EXTERNAL_DOMAIN__" ]
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
    after = [ "mosquitto.service" ];
    requires = [ "mosquitto.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

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

  systemd.tmpfiles.rules = [
    "L+ ${hassDir}/automations - - - - ${hassGenerated}/automations"
    "L+ ${hassDir}/scripts - - - - ${hassGenerated}/scripts"
    "L+ ${hassDir}/scenes - - - - ${hassGenerated}/scenes"
    "d ${hassDir}/.storage 0755 hass hass -"
    "d ${hassDir}/backups 0755 hass hass -"
    "d ${hassDir}/logs 0755 hass hass -"
    "d ${hassDir}/www 0755 hass hass -"
  ];

  system.activationScripts.home-assistant-config = {
    text = ''
      mkdir -p ${hassDir}
      ln -sfn ${hassGenerated}/automations ${hassDir}/automations
      ln -sfn ${hassGenerated}/scripts ${hassDir}/scripts
      ln -sfn ${hassGenerated}/scenes ${hassDir}/scenes
      ${pkgs.coreutils}/bin/install -Dm644 ${
        config.sops.templates."hass-configuration.yaml".path
      } ${hassDir}/configuration.yaml
      mkdir -p ${hassDir}/.storage ${hassDir}/backups ${hassDir}/logs ${hassDir}/www
    '';
    deps = [ "users" ];
  };

  networking.firewall.allowedTCPPorts = [ 8123 ];

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
        server = "mqtt://localhost:1883";
      };
      serial = {
        port = zigbeeDongle;
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
