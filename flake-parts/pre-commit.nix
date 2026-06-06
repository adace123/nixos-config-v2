{ inputs, ... }:
{
  imports = [
    inputs.git-hooks.flakeModule
  ];

  perSystem =
    {
      config,
      lib,
      pkgs,
      inputs',
      ...
    }:
    {
      # Pre-commit hooks configuration
      pre-commit.settings.hooks = {
        # Format Nix code
        nixfmt.enable = true;

        # Lint Nix code with auto-fix
        statix = {
          enable = true;
          args = [ "fix" ]; # Enable auto-fixing of issues
        };

        # Find dead Nix code
        deadnix.enable = true;

        # Check for merge conflicts
        check-merge-conflicts.enable = true;

        # Ensure files end with newline
        end-of-file-fixer.enable = true;

        # Check for case conflicts in filenames
        check-case-conflicts.enable = true;

        # shellcheck for shell script analysis
        shellcheck = {
          enable = true;
          types = [ "shell" ]; # Check shell script files
        };

        # Shell script formatter
        shfmt = {
          enable = true;
          types = [ "shell" ]; # Format shell script files
        };

        # MD
        markdownlint = {
          enable = true;
          entry = "${pkgs.markdownlint-cli2}/bin/markdownlint-cli2";
          types = [ "markdown" ];
          args = [
            "--fix"
            "--config"
            "./.markdownlint.json"
          ];
        };

        # yaml - auto-formats yaml files
        yamlfmt = {
          enable = true;
          types = [ "yaml" ]; # Format YAML files
          files = ''.*\.(yaml|yml)$''; # Regex to match both .yaml and .yml files
          args = [ ]; # Default args, yamlfmt should format by default
        };
      };

      # Use alternative pre-commit implementation
      pre-commit.settings.package = pkgs.prek;

      # Add pre-commit hooks to devShell
      devShells.default = pkgs.mkShell {
        inputsFrom = [
          config.pre-commit.devShell
        ];

        packages =
          with pkgs;
          [
            # Nix tools
            nil
            nixd

            # Development utilities
            git
            just

            # Documentation
            mdbook
          ]
          ++ lib.optionals pkgs.stdenv.isDarwin [
            inputs'.darwin.packages.darwin-rebuild
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
