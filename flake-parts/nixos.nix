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
        ({ host, ... }: {
          networking.hostName = host.hostName;
          services.cloud-init.enable = true;
          services.openssh.settings.PermitRootLogin = "no";
        })
      ];
    };
  };
}
