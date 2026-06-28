{ inputs, ... }:
let
  hosts = import ../hosts;
  coruscantHost = hosts.coruscant;
  dathomirHost = hosts.dathomir;
  nixos-raspberrypi = inputs.nixos-raspberrypi;

  mkPiSystem =
    host: modules:
    inputs.nixpkgs.lib.nixosSystem {
      system = host.system;
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
      system = host.system;
      specialArgs = {
        inherit inputs host;
      }
      // extraSpecialArgs;
      inherit modules;
    };
in
{
  flake.nixosConfigurations = {
    "${coruscantHost.hostName}" = mkPiSystem coruscantHost [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/ssd.nix
    ];

    "${coruscantHost.hostName}-sd-image" = mkPiSystem coruscantHost [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.sd-image
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/installer.nix
    ];

    "${dathomirHost.hostName}" = mkSystem dathomirHost {
      modules = [
        "${inputs.nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        ({ host, pkgs, ... }: {
          networking.hostName = host.hostName;
          services.cloud-init.enable = true;
          services.tailscale = {
            enable = true;
            openFirewall = true;
          };
          systemd.services.tailscale-autoconnect = {
            description = "Connect to Tailscale";
            after = [
              "cloud-final.service"
              "network-online.target"
              "tailscaled.service"
            ];
            wants = [
              "network-online.target"
              "tailscaled.service"
            ];
            wantedBy = [ "multi-user.target" ];
            path = [ pkgs.tailscale ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              if tailscale status --peers=false >/dev/null 2>&1; then
                exit 0
              fi
              for _ in $(seq 1 120); do
                [ -s /var/lib/tailscale/authkey ] && break
                sleep 1
              done
              tailscale up --auth-key "$(cat /var/lib/tailscale/authkey)" --ssh --hostname ${host.hostName}
            '';
          };
          services.openssh.settings.PermitRootLogin = "no";
        })
      ];
    };
  };
}
