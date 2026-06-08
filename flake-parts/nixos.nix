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
        inputs.sops-nix.nixosModules.sops
        ../modules/nixos/coruscant.nix
      ];
    };

    coruscant-sd-image = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs nixos-raspberrypi; };
      modules = [
        nixos-raspberrypi.lib.inject-overlays
        nixos-raspberrypi.nixosModules.raspberry-pi-4.base
        nixos-raspberrypi.nixosModules.sd-image
        inputs.sops-nix.nixosModules.sops
        ../modules/nixos/installer.nix
      ];
    };

    coruscant-ssd = inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs nixos-raspberrypi; };
      modules = [
        nixos-raspberrypi.lib.inject-overlays
        nixos-raspberrypi.nixosModules.raspberry-pi-4.base
        inputs.sops-nix.nixosModules.sops
        ../modules/nixos/coruscant-ssd.nix
      ];
    };
  };
}
