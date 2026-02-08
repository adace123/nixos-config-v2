{ inputs, ... }:

{
  perSystem = { pkgs, inputs', system, ... }: {
    # Development shell
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        # Nix tools
        nil
        nixpkgs-fmt
        nixd
	inputs'.darwin.packages.darwin-rebuild

        # Development utilities
        git
        just
      ];

      shellHook = ''
        echo "🚀 Welcome to nixos-config-v2 development shell"
        echo ""
        echo "Available commands:"
        echo "  just                - List all just commands"
        echo "  just check          - Run all checks"
        echo "  just switch         - Apply configuration"
        echo "  nixpkgs-fmt <file>  - Format Nix files"
        echo ""
      '';
    };
  };

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
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.aaron = {
            imports = [ ../modules/home ];
            home = {
              username = "aaron";
              homeDirectory = "/Users/aaron";
            };
          };
          home-manager.extraSpecialArgs = { inherit inputs; };
        }
      ];
    };
  };
}
