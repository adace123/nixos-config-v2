{ inputs, ... }:
{
  flake.darwinConfigurations = {
    endor = inputs.darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit inputs; };
      modules = [
        ../modules/darwin
        inputs.home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [
            inputs.zed-extensions.overlays.default
          ];

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            sharedModules = [
              inputs.zed-extensions.homeManagerModules.default
            ];
            users.aaron = {
              imports = [ ../modules/home ];
              home = {
                username = "aaron";
                homeDirectory = "/Users/aaron";
              };
            };
            extraSpecialArgs = { inherit inputs; };
          };
        }
      ];
    };
  };
}
