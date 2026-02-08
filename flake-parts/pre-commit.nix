{ inputs, ... }:
{
  imports = [
    inputs.git-hooks.flakeModule
  ];

  perSystem =
    {
      config,
      pkgs,
      inputs',
      ...
    }:
    {
      # Pre-commit hooks configuration
      pre-commit.settings.hooks = {
        # Format Nix code
        nixfmt.enable = true;

        # Lint Nix code
        statix.enable = true;

        # Find dead Nix code
        deadnix.enable = true;

        # Check for merge conflicts
        check-merge-conflicts.enable = true;

        # Ensure files end with newline
        end-of-file-fixer.enable = true;

        # Check for case conflicts in filenames
        check-case-conflicts.enable = true;

        # shellcheck
        shellcheck.enable = true;
      };

      # Use alternative pre-commit implementation
      pre-commit.settings.package = pkgs.prek;

      # Add pre-commit hooks to devShell
      devShells.default = pkgs.mkShell {
        inputsFrom = [
          config.pre-commit.devShell
        ];

        packages = with pkgs; [
          # Nix tools
          nil
          nixd
          inputs'.darwin.packages.darwin-rebuild

          # Development utilities
          git
          just

          # Documentation
          mdbook
        ];

        shellHook = ''
          echo "🚀 Welcome to nixos-config-v2 development shell"
          echo ""
          echo "✓ Pre-commit hooks installed!"
          echo "  Run 'pre-commit run --all-files' to check all files"
          echo ""
          echo "Available commands:"
          echo "  just                - List all just commands"
          echo "  just check          - Run all checks"
          echo "  just switch         - Apply configuration"
          echo ""
        '';
      };
    };
}
