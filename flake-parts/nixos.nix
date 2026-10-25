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
                  # Generated once and never printed; Pocket ID reads it through a
                  # systemd credential, so it stays out of the Nix store.
                  pocket-id-encryption-key = { };
                  pocket-id-domain = { };
                };
              };

              # Pocket ID: passkey-based identity provider, which is what gives the
              # hub its passkey login. Published on the tailnet exactly like the hub
              # — a public name whose A record points at this host's Tailscale
              # address — with its certificate from the same Cloudflare DNS-01 setup.
              # APP_URL carries the domain, which lives in sops. A sops *placeholder*
              # is only substituted inside sops-rendered content (templates/files) —
              # put it in an ordinary settings attrset and the literal placeholder
              # Pocket ID wants a full URL, and a credential is read verbatim — so the
              # scheme has to be in the file the credential points at, not just the
              # bare hostname that the DNS record and Caddy vhost need. Hence a
              # template: pointing APP_URL at the domain secret itself gave
              # "APP_URL must not contain a path", because a scheme-less string parses
              # as one.
              sops.templates."pocket-id-app-url" = {
                content = "https://${config.sops.placeholder.pocket-id-domain}";
              };

              services.pocket-id = {
                enable = true;
                settings = {
                  PORT = 1411;
                  # Behind Caddy, so it must trust forwarded headers.
                  TRUST_PROXY = true;
                  ANALYTICS_DISABLED = true;
                };
                credentials = {
                  # Neither value may enter the store, so both are handed over as
                  # systemd credentials built from sops-rendered files.
                  ENCRYPTION_KEY = config.sops.secrets.pocket-id-encryption-key.path;
                  # APP_URL goes through `credentials` rather than `settings` because a
                  # settings value is rendered into the store at build time (so a sops
                  # placeholder could not be substituted) *and* the module appends its
                  # own settings file after this host's, where its
                  # `APP_URL = http://localhost` default would win. Credentials are
                  # exported inside the start script, after EnvironmentFile is applied.
                  APP_URL = config.sops.templates."pocket-id-app-url".path;
                };
              };

              # Beszel hub, published to the tailnet only. Caddy terminates TLS for
              # the Cloudflare-managed name — whose A record deliberately points at
              # this host's tailnet address, so the name resolves but is unroutable
              # outside the tailnet — and proxies the hub, which stays on localhost.
              services.beszel.hub = {
                enable = true;
                # Upstream release binaries (0.21.0 has the service-logs panel;
                # nixpkgs only has 0.20.0). Shared definition in nix-beszel.nix.
                package = import ../nix-beszel.nix { inherit pkgs; };
                host = "127.0.0.1";
                port = 8090;
                # OAuth accounts are created on first login. The client itself is
                # configured in the hub's own settings (see docs/dathomir.md) because
                # it lives in the hub database, not here.
                #
                # DISABLE_PASSWORD_AUTH is deliberately NOT set yet: turning it on
                # before a passkey login has been verified locks everyone out.
                environment.USER_CREATION = "true";
                # The hub builds notification links from APP_URL and falls back to
                # http://localhost:8090, which is useless from a phone: every beszel
                # alert carried a dead link until this was set (2026-10-23). It comes
                # from the beszel-domain secret via a template so the name stays out
                # of the repo; systemd reads EnvironmentFile as root, so the hub's
                # DynamicUser can stay.
                environmentFile = config.sops.templates."beszel-hub-env".path;
              };

              sops.templates."beszel-hub-env" = {
                content = ''
                  APP_URL=https://${config.sops.placeholder.beszel-domain}
                '';
                mode = "0400";
              };

              # External liveness check for coruscant, run from a *different* machine.
              # The hub only knows what the agent tells it, so a host whose agent is
              # healthy while its services are dead reads "up" — that is the gap that
              # let the 2026-10-18 outage sit unnoticed for five days. This pokes the
              # tailnet address and the SSH port; it exits non-zero on failure, and a
              # failed unit is what the beszel SystemdFailed alert turns into a phone
              # notification.
              #
              # No SSH key on purpose (only a TCP connect), so the check cannot rot
              # when credentials are rotated. Limitation: a box whose filesystem has
              # stopped accepting writes can still complete a TCP handshake — that is
              # what the storage canary on the host itself is for.
              systemd.services.coruscant-reachability = {
                description = "Check that coruscant answers over the tailnet";
                path = with pkgs; [
                  bash
                  coreutils
                  iputils
                ];
                serviceConfig.Type = "oneshot";
                script = ''
                  set -eu
                  ping -c2 -W2 100.66.226.84 >/dev/null
                  timeout 5 bash -c 'exec 3<>/dev/tcp/100.66.226.84/22'
                '';
              };
              systemd.timers.coruscant-reachability = {
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnBootSec = "10m";
                  OnUnitActiveSec = "10m";
                  RandomizedDelaySec = "1m";
                  Unit = "coruscant-reachability.service";
                };
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

                  ${config.sops.placeholder.pocket-id-domain} {
                    reverse_proxy 127.0.0.1:1411
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
                config.sops.secrets.pocket-id-domain.path
                # A sops template is rewritten on every activation but keeps the same
                # path, so a change to the template itself is invisible to systemd and
                # Caddy would go on serving the old config until something else
                # restarted it. This store path is keyed by the template's own text,
                # so it changes exactly when the Caddyfile does.
                (pkgs.writeText "caddyfile-source" config.sops.templates."caddyfile".content)
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
        ]
        # The agent is gated on the same per-host flag the Pi hosts use, because its
        # key is minted by the hub and a declared-but-missing secret fails
        # activation — so the hub has to be deployed, and a system added to it,
        # before the agent can be switched on here.
        ++ inputs.nixpkgs.lib.optional (dathomirHost.beszelAgent or false) ../modules/nixos/beszel-agent.nix
        # The hub's own state — users, alert rules, and the keypair every agent
        # verifies — exists only in its PocketBase data dir, so it gets a restic job
        # of its own. Unconditional: the hub always runs on this host.
        ++ [ ../modules/nixos/beszel-hub-restic.nix ];
      };
    };
}
