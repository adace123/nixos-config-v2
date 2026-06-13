{ inputs, ... }:
let
  hosts = import ../hosts;
  host = hosts.endor;
in
{
  flake.darwinConfigurations = {
    "${host.hostName}" = inputs.darwin.lib.darwinSystem {
      system = host.system;
      specialArgs = { inherit inputs host; };
      modules = [
        ../modules/darwin
        inputs.sops-nix.darwinModules.sops
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
              inputs.sops-nix.homeManagerModules.sops
              inputs.zed-extensions.homeManagerModules.default
            ];
            users.${host.user.name} = {
              imports = [ ../modules/home ];
              home = {
                username = host.user.name;
                homeDirectory = host.user.homeDirectory;
              };
            };
            extraSpecialArgs = { inherit inputs host; };
          };
        }
      ];
    };

  };
}
