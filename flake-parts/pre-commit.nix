{ inputs, ... }:

{
  imports = [
    inputs.pre-commit-hooks.flakeModule
  ];

  perSystem =
    { config, pkgs, ... }:
    {
      # Pre-commit hooks configuration
      pre-commit = {
        check.enable = true;

        settings = {
          hooks = {
            # Nix formatting
            nixpkgs-fmt = {
              enable = true;
            };

            # Nix linting - disabled due to build issues
            # statix = {
            #   enable = true;
            # };

            # Dead code detection - disabled due to build issues
            # deadnix = {
            #   enable = true;
            # };

            # Check for merge conflicts
            check-merge-conflicts = {
              enable = true;
            };

            # Ensure files end with newline
            end-of-file-fixer = {
              enable = true;
            };

            # Check for case conflicts in filenames
            check-case-conflicts = {
              enable = true;
            };
          };

          # Exclude patterns
          excludes = [
            "flake.lock"
            ".direnv/"
            "result"
            "result-*"
          ];
        };
      };

      # Add pre-commit hooks to devShell
      devShells.default = pkgs.mkShell {
        inputsFrom = [
          config.pre-commit.devShell
        ];

        packages = with pkgs; [
          # Nix tools
          nil
          nixpkgs-fmt
          nixd
          # statix  # Disabled due to build issues
          # deadnix # Disabled due to build issues

          # Development utilities
          git
          just

          # Documentation
          mdbook
        ];

        shellHook = ''
          ${config.pre-commit.installationScript}

          echo "🚀 Welcome to nixos-config-v2 development shell"
          echo ""
          echo "✓ Pre-commit hooks are installed!"
          echo "  Run 'pre-commit run --all-files' to check all files"
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
}
