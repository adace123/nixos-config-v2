{ inputs, ... }:
let
  hosts = import ../hosts;
  host = hosts.coruscant;
  nixos-raspberrypi = inputs.nixos-raspberrypi;

  mkPiSystem =
    modules:
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
    "${host.hostName}" = mkPiSystem [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/${host.hostName}/ssd.nix
    ];

    "${host.hostName}-sd-image" = mkPiSystem [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.sd-image
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/${host.hostName}/installer.nix
    ];

    oci-base = mkSystem {
      modules = [
        "${inputs.nixpkgs}/nixos/modules/virtualisation/oci-image.nix"
        ../modules/nixos/oci-image/configuration.nix
      ];
    };
  };
}
