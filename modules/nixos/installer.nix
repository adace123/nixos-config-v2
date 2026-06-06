{ lib, pkgs, ... }:
let
  ageKey = ../../nixos-files/var/lib/sops/age-key.txt;
  hasAgeKey = builtins.pathExists ageKey;
in
{
  imports = [
    ./common.nix
  ];

  config = lib.mkMerge [
    {
      # Use stock kernel (from cache.nixos.org) instead of vendor RPi kernel
      # to avoid building the vendor kernel from source under QEMU emulation.
      boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

      networking.hostName = "coruscant-installer";
      networking.useDHCP = true;

      # Enable mDNS for local network discovery
      services.avahi = {
        enable = true;
        hostName = "coruscant-installer";
        publish = {
          enable = true;
          workstation = true;
          addresses = true;
          domain = true;
        };
      };

      # Root filesystem
      fileSystems."/" = {
        device = "/dev/disk/by-label/NIXOS_SD";
        fsType = "ext4";
      };

      # Timezone
      time.timeZone = "UTC";

      # Minimal firewall — just mDNS
      networking.firewall = {
        enable = true;
        allowedUDPPorts = [ 5353 ];
      };
    }

    # WiFi + sops-nix — only when age key is available (local build).
    # CI builds fall back to Ethernet-only.
    (lib.mkIf hasAgeKey {
      sops = {
        defaultSopsFile = ../secrets/default.yaml;
        age.keyFile = "/var/lib/sops/age-key.txt";
        secrets."wpa-supplicant" = {
          neededForUsers = true;
        };
      };

      networking.wireless = {
        enable = true;
        extraConfigFiles = [
          "/run/secrets/wpa-supplicant"
        ];
      };

      systemd.services.wpa_supplicant = {
        wants = [ "sops-init.service" ];
        after = [ "sops-init.service" ];
      };

      system.activationScripts.sops-age-key = {
        deps = [ "users" ];
        text = ''
          mkdir -p /var/lib/sops
          ${pkgs.coreutils}/bin/cp "${ageKey}" /var/lib/sops/age-key.txt
          ${pkgs.coreutils}/bin/chmod 0400 /var/lib/sops/age-key.txt
        '';
      };
    })
  ];
}
