{ inputs, ... }:
let
  nixos-raspberrypi = inputs.nixos-raspberrypi;
  mkPiSystem =
    modules:
    inputs.nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      specialArgs = { inherit inputs nixos-raspberrypi; };
      inherit modules;
    };
in
{
  flake.nixosConfigurations = {
    coruscant = mkPiSystem [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/coruscant/ssd.nix
    ];

    coruscant-sd-image = mkPiSystem [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.sd-image
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/coruscant/installer.nix
    ];

    coruscant-ssd = mkPiSystem [
      nixos-raspberrypi.lib.inject-overlays
      nixos-raspberrypi.nixosModules.raspberry-pi-4.base
      nixos-raspberrypi.nixosModules.trusted-nix-caches
      inputs.sops-nix.nixosModules.sops
      ../modules/nixos/coruscant/ssd.nix
    ];
  };
}
