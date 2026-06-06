{ inputs, ... }:
let
  nixos-raspberrypi = inputs.nixos-raspberrypi;
in
{
  flake.nixosConfigurations = {
    coruscant = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs nixos-raspberrypi; };
      modules = [
        nixos-raspberrypi.lib.inject-overlays
        nixos-raspberrypi.nixosModules.raspberry-pi-4.base
        nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
        ../modules/nixos/coruscant.nix
      ];
    };

    coruscant-sd-image = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs nixos-raspberrypi; };
      modules = [
        nixos-raspberrypi.lib.inject-overlays
        nixos-raspberrypi.nixosModules.raspberry-pi-4.base
        nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
        nixos-raspberrypi.nixosModules.sd-image
        ../modules/nixos/installer.nix
      ];
    };
  };
}
