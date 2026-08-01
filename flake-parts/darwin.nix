{ inputs, ... }:
let
  hosts = import ../hosts;
  host = hosts.endor;
in
{
  flake.darwinConfigurations = {
    "${host.hostName}" = inputs.darwin.lib.darwinSystem {
      inherit (host) system;
      specialArgs = { inherit inputs host; };
      modules = [
        ../modules/darwin
        inputs.sops-nix.darwinModules.sops
        inputs.home-manager.darwinModules.home-manager
        {
          nixpkgs.overlays = [
            inputs.zed-extensions.overlays.default
          ];

          nixpkgs.config.allowBroken = true;

          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            # Hermes (and other tools) atomic-replace their config symlink and
            # leave a read-only .bak (0444). Home-manager's backup step is
            # `mv target target.bak` (no -f); BSD mv prompts on a read-only
            # destination and hangs activation. overwriteBackup makes it `rm`
            # the stale .bak first, so the mv is a clean rename.
            overwriteBackup = true;
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
