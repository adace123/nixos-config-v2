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
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
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
