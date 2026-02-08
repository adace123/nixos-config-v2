{ inputs, ... }:
{
  flake.darwinConfigurations = {
    # Hostname: enervee-ltqcw2y7pv
    # You can find it by running: scutil --get LocalHostName
    enervee-ltqcw2y7pv = inputs.darwin.lib.darwinSystem {
      system = "aarch64-darwin"; # or "x86_64-darwin" for Intel Macs
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
