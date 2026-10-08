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
      # Formatter used by `nix fmt` (kept in sync with the pre-commit nixfmt hook)
      # nixfmt-tree discovers the git tree itself — bare nixfmt reads stdin and
      # breaks `nix fmt` (empty input parse error).
      formatter = pkgs.nixfmt-tree;

      # Pre-commit hooks configuration
      pre-commit.settings.hooks = {
        # Format Nix code
        nixfmt.enable = true;

        # Lint Nix code. This is git-hooks.nix's built-in hook, whose entry is
        # `statix check --format errfmt` with pass_filenames = false — statix
        # accepts a single target, so it checks the whole tree (honouring
        # .gitignore) instead of the staged files.
        #
        # Do NOT add `args = [ "fix" ]` to this hook. pre-commit appends args as
        # extra argv after the entry, so statix reads "fix" as its TARGET path,
        # prints `config error: path error: file not found: fix` and still exits
        # 0 — a silent no-op that checked nothing. There is no fix mode in the
        # built-in hook; run `statix fix` by hand to apply suggestions.
        #
        # `statix.toml` (repo root, picked up by statix's default `-c .`) turns
        # off `repeated_keys`; everything else statix reports must be fixed,
        # because `nix flake check` runs these hooks over the whole tree.
        statix.enable = true;

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

        # The herdr-kanban board's own checks (its `--selftest` and the
        # protocol-sync comparison) are `nix flake check` outputs in
        # adace123/herdr-kanban, gated by that repo's CI. They used to be hooks
        # here, with `files` patterns that could only ever match files in this
        # repo — so a plugin change made in the plugin repo was never checked by
        # them anyway.

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
