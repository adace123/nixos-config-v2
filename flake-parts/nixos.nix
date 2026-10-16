{ inputs, ... }:
let
  hosts = import ../hosts;
  coruscantHost = hosts.coruscant;
  dathomirHost = hosts.dathomir;
  threepioHost = hosts.threepio;
  inherit (inputs) nixos-raspberrypi;

  mkPiSystem =
    host: modules:
    inputs.nixpkgs.lib.nixosSystem {
      inherit (host) system;
      specialArgs = {
        inherit
          inputs
          host
          nixos-raspberrypi
          ;
      };
      inherit modules;
    };

  mkSystem =
    host:
    {
      modules,
      extraSpecialArgs ? { },
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit (host) system;
      specialArgs = {
        inherit inputs host;
      }
      // extraSpecialArgs;
      inherit modules;
    };

  # Modules shared by every Raspberry Pi / Turing Pi node configuration.
  piBaseModules = [
    nixos-raspberrypi.lib.inject-overlays
    nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    nixos-raspberrypi.nixosModules.trusted-nix-caches
    inputs.sops-nix.nixosModules.sops
  ];
  sdImageModule = nixos-raspberrypi.nixosModules.sd-image;

  # Build both the running-system config and its bootable sd-image variant for
  # a Pi host. systemModule is the storage module for the running system
  # (e.g. ssd.nix or sd.nix); imageModule is what the sd-image bakes — the
  # installer module, or the storage module itself for SD-booted nodes.
  mkPiHost =
    host:
    {
      systemModule,
      imageModule,
    }:
    {
      "${host.hostName}" = mkPiSystem host (piBaseModules ++ [ systemModule ]);
      "${host.hostName}-sd-image" = mkPiSystem host (
        piBaseModules
        ++ [
          sdImageModule
          imageModule
        ]
      );
    };
in
{
  flake.nixosConfigurations =
    mkPiHost coruscantHost {
      systemModule = ../modules/nixos/ssd.nix;
      imageModule = ../modules/nixos/installer.nix;
    }
    // mkPiHost threepioHost {
      systemModule = ../modules/nixos/sd.nix;
      imageModule = ../modules/nixos/sd.nix;
    }
    // {
      # dathomir boots an Oracle *platform* image (Ubuntu) on an Always Free
      # tenancy and is converted to NixOS in place by scripts/dathomir-convert.sh —
      # an Always Free tenancy has custom-image-count = 0, so the former
      # "build a qcow2, import it as a custom image" path could never work. Hence
      # no virtualisation/oci-image.nix here and no OCIImage output to build.
      # See docs/dathomir.md.
      "${dathomirHost.hostName}" = mkSystem dathomirHost {
        modules = [
          inputs.sops-nix.nixosModules.sops
          # Runs the beszel agent here as well as the hub, so the box reports to
          # itself (and needs its own beszel-agent-key in secrets/dathomir.yaml).
          ../modules/nixos/beszel-agent.nix
          (
            {
              config,
              host,
              pkgs,
              ...
            }:
            let
              caches = import ../nix-caches.nix;
            in
            {
              networking.hostName = host.hostName;
              system.stateVersion = "24.11";

              # The platform image's partition layout, which nixos-infect keeps: it
              # installs over the existing layout instead of repartitioning, so the
              # flake configuration has to describe the same thing. These are the
              # labels Oracle's Ubuntu image actually uses — confirmed on a live
              # instance, and the same view its own /etc/fstab takes:
              #   sda1  cloudimg-rootfs  ext4  /
              #   sda16 BOOT             ext4  /boot
              #   sda15 UEFI             vfat  /boot/efi
              # Note /boot is its own partition, and there is no by-partlabel
              # directory on this image — the ESP is named by filesystem label.
              fileSystems."/" = {
                device = "/dev/disk/by-label/cloudimg-rootfs";
                fsType = "ext4";
              };
              fileSystems."/boot" = {
                device = "/dev/disk/by-label/BOOT";
                fsType = "ext4";
              };
              fileSystems."/boot/efi" = {
                device = "/dev/disk/by-label/UEFI";
                fsType = "vfat";
              };

              # UEFI boot without NVRAM access: install grub on the removable
              # path. nixos-infect generates the same settings for the bootstrap
              # system, so both agree about where to boot from.
              boot.loader = {
                efi.efiSysMountPoint = "/boot/efi";
                grub = {
                  enable = true;
                  efiSupport = true;
                  efiInstallAsRemovable = true;
                  device = "nodev";
                  # /boot on this image is a ~900 MB partition (sda16) and every
                  # generation drops a kernel and an initrd into it, so bound it the
                  # way the Pi hosts do — a full /boot makes rebuilds fail.
                  configurationLimit = 5;
                };
              };
              boot.initrd.availableKernelModules = [
                "nvme"
                "virtio_blk"
                "virtio_scsi"
              ];

              # Root SSH with keys is what `just nixos-deploy` needs. The instance
              # has no public IP, so only tailnet peers can reach either account.
              users.users.root.openssh.authorizedKeys.keys = host.sshPublicKeys;
              users.users.nixos = {
                isNormalUser = true;
                extraGroups = [ "wheel" ];
                openssh.authorizedKeys.keys = host.sshPublicKeys;
              };
              security.sudo.wheelNeedsPassword = false;

              services.openssh = {
                enable = true;
                settings = {
                  PermitRootLogin = "prohibit-password";
                  PasswordAuthentication = false;
                };
              };

              services.tailscale = {
                enable = true;
                openFirewall = true;
                # Seeded by scripts/dathomir-convert.sh from the key cloud-init
                # wrote, which survives the conversion in /etc/nixos. Only used if
                # the preserved /var/lib/tailscale node identity is unavailable.
                authKeyFile = "/etc/nixos/tailscale-authkey";
                extraUpFlags = [ "--ssh" ];
              };

              # The tailnet is the only way in, so trust it. `services.tailscale.
              # openFirewall` above only opens WireGuard's UDP port — not the
              # interface — so without this Caddy's 443 would be firewalled off from
              # exactly the clients meant to reach it.
              networking.firewall.trustedInterfaces = [ "tailscale0" ];

              # Secrets for the Cloudflare DNS-01 challenge below. The host's age key
              # is installed once by hand at /var/lib/sops-nix/key.txt; nothing
              # decrypts without it.
              sops = {
                defaultSopsFile = ../secrets/dathomir.yaml;
                age.keyFile = "/var/lib/sops-nix/key.txt";
                secrets = {
                  beszel-domain = { };
                  cloudflare-api-key = { };
                };
              };

              # Beszel hub, published to the tailnet only. Caddy terminates TLS for
              # the Cloudflare-managed name — whose A record deliberately points at
              # this host's tailnet address, so the name resolves but is unroutable
              # outside the tailnet — and proxies the hub, which stays on localhost.
              services.beszel.hub = {
                enable = true;
                host = "127.0.0.1";
                port = 8090;
              };

              sops.templates."caddy-env" = {
                content = ''
                  CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare-api-key}
                '';
                owner = "caddy";
                group = "caddy";
                mode = "0400";
              };

              sops.templates."caddyfile" = {
                content = ''
                  {
                    acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
                  }

                  ${config.sops.placeholder.beszel-domain} {
                    reverse_proxy 127.0.0.1:8090
                  }
                '';
                owner = "caddy";
                group = "caddy";
                mode = "0400";
              };

              services.caddy = {
                enable = true;
                openFirewall = true;
                configFile = config.sops.templates."caddyfile".path;
                # The Cloudflare DNS plugin, defined once in nix-caddy.nix.
                package = import ../nix-caddy.nix { inherit pkgs; };
                environmentFile = config.sops.templates."caddy-env".path;
              };

              systemd.services.caddy.restartTriggers = [
                config.sops.secrets.cloudflare-api-key.path
                config.sops.secrets.beszel-domain.path
              ];

              nix = {
                gc = {
                  automatic = true;
                  dates = "weekly";
                  options = "--delete-older-than 14d";
                };
                settings = {
                  auto-optimise-store = true;
                  # Single source of truth: nix-caches.nix (also used by flake.nix
                  # `nixConfig` and modules/home/default.nix).
                  inherit (caches) extra-substituters;
                  inherit (caches) extra-trusted-public-keys;
                };
              };

              time.timeZone = "America/Los_Angeles";
            }
          )
        ];
      };
    };
}
