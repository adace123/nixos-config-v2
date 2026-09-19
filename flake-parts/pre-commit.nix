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
    let
      # The kanban board's headless checks. Built here so the hook runs the same
      # packaged artifact the herdr plugin launches, not the working tree.
      kanban = import ../modules/home/ai/herdr/kanban-package.nix { inherit pkgs; };
    in
    {
      # Formatter used by `nix fmt` (kept in sync with the pre-commit nixfmt hook)
      # nixfmt-tree discovers the git tree itself — bare nixfmt reads stdin and
      # breaks `nix fmt` (empty input parse error).
      formatter = pkgs.nixfmt-tree;

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

        # Detect accidentally committed secrets and credentials
        gitleaks = {
          enable = true;
          name = "gitleaks";
          description = "Detect hardcoded secrets in staged changes";
          entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --staged --redact";
          pass_filenames = false; # scans the staged diff itself
        };

        # Keep flake.nix nixConfig in sync with nix-caches.nix (the source of
        # truth). flake.nix must duplicate the lists because nix reads
        # nixConfig without evaluating imports.
        check-nix-caches-sync = {
          enable = true;
          name = "check-nix-caches-sync";
          description = "Verify flake.nix nixConfig matches nix-caches.nix";
          entry = "${pkgs.bash}/bin/bash ${../scripts/check-nix-caches-sync.sh}";
          files = "^(flake\.nix|nix-caches\.nix)$";
          pass_filenames = false;
        };

        # The board is launched into a herdr pane, so anything broken at import
        # or in the store/render paths shows up as a pane that opens and closes.
        # These run the packaged app (its own store build, so a module the flake
        # cannot see fails here too) whenever the plugin changes.
        kanban-selftest = {
          enable = true;
          name = "kanban-selftest";
          description = "Run the herdr-kanban board's headless checks";
          entry = "${kanban.cli}/bin/herdr-kanban --selftest";
          files = "^(modules/home/ai/herdr/plugins/kanban/|modules/home/ai/herdr/kanban-package\.nix)";
          pass_filenames = false;
        };

        # The board protocol is both documentation and a prompt an agent acts on:
        # it lives in the Python source and is quoted in docs/kanban.md, and it
        # has drifted before. This fails when the two disagree, so the docs
        # cannot promise an agent something the prompt never tells it.
        check-kanban-protocol-sync = {
          enable = true;
          name = "check-kanban-protocol-sync";
          description = "Verify the protocol in docs/kanban.md matches PROTOCOL_TEMPLATE";
          entry = "${pkgs.bash}/bin/bash ${../scripts/check-kanban-protocol-sync.sh} ${kanban.python}/bin/python ${kanban.app}/share/herdr-kanban";
          files = "^(docs/kanban\.md|scripts/check-kanban-protocol-sync\.sh|modules/home/ai/herdr/plugins/kanban/)";
          pass_filenames = false;
        };

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

        # Terraform lint
        tflint = {
          enable = true;
          types = [ "terraform" ]; # Lint Terraform files
        };

        # yaml - auto-formats yaml files
        yamlfmt = {
          enable = true;
          types = [ "yaml" ]; # Format YAML files
          settings.lint-only = false; # Actually format files, not just check
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

            # Secrets management (sops-nix)
            age
            sops
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
