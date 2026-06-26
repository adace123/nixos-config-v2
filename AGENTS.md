# AGENTS.md - Guidelines for Agentic Coding Agents

This file contains guidelines, commands, and conventions for agentic coding agents working in this NixOS/nix-darwin configuration repository.

## Repository Overview

This is a Nix flake-based configuration for managing macOS systems using nix-darwin and home-manager. The configuration includes system packages, user environment, development tools, and optional modules.

## Build/Test/Lint Commands

### Primary Commands

- `just check` - Run all checks (flake check, format, lint, pre-commit); `just validate` is an alias
- `nix flake check --all-systems` - Check flake for errors across all systems
- `nh darwin build` - Build configuration without activating (requires manual activation via `just switch` which needs password)
- `nh clean` - Enhanced garbage collection with better UX
- `nh search <pkg>` - Fast package search via Elasticsearch

### Formatting Commands

- `just fmt` - Format all Nix files via justfile

### Linting Commands

- `statix` - Lint Nix code (via pre-commit)
- `deadnix` - Find dead/unused Nix code
- `shellcheck` - Lint shell scripts
- `markdownlint` - Lint Markdown files
- `yamlfmt` - Format YAML files

### Pre-commit Hooks

- `pre-commit run --all-files` - Run all hooks on all files
- `pre-commit install` - Install hooks
- `pre-commit uninstall` - Uninstall hooks

### Development Commands

- `nix develop` - Enter development shell
- `just dev` - Enter dev shell via justfile
- `just update` - Update flake inputs
- `just update-input <input>` - Update specific input

### Testing

- No traditional test suite - validation done via `nix flake check`
- Configuration tested by building/activating with `nh darwin`

## Code Style Guidelines

### Nix File Structure

- Use 2-space indentation
- Prefer trailing commas in lists and attribute sets
- Order imports: standard library first, then local modules
- Use consistent attribute ordering: `config`, `pkgs`, `lib`, `...`

### Import Conventions

```nix
# Standard import pattern
{ config, pkgs, ... }:
{
  imports = [
    # Local modules first
    ./module1.nix
    ./module2.nix
  ];
}
```

### Package Management

- System packages: Add to `environment.systemPackages` in `modules/darwin/default.nix`
- User packages: Add to `home.packages` in `modules/home/default.nix`
- Homebrew: Add to appropriate lists in `modules/darwin/homebrew.nix`

### Naming Conventions

- Files: kebab-case (e.g., `core-settings.nix`, `auto-update.nix`)
- Modules: camelCase for attributes, kebab-case for filenames
- Variables: camelCase for Nix variables, UPPER_CASE for environment variables

### Attribute Set Style

```nix
# Good: Clear structure with comments
programs = {
  zsh = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      update = "nh darwin switch";
    };
  };
};

# Good: Use with-pkgs for package lists
home.packages = with pkgs; [
  ripgrep
  fd
  jq
];
```

### Error Handling

- Use `lib.optionalAttrs` for conditional configuration
- Prefer `mkIf` for conditional module inclusion
- Use `mkDefault` for overrideable defaults

### Configuration Patterns

```nix
# Conditional configuration
config = lib.mkIf config.programs.zsh.enable {
  # ... zsh config
};

# Optional configuration with defaults
programs.starship = {
  enable = true;
  enableBashIntegration = lib.mkDefault true;
};

# Environment variables
home.sessionVariables = {
  EDITOR = "nvim";
  DIRENV_LOG_FORMAT = "";
};
```

## Common Patterns

### Package Installation

```nix
# System packages
environment.systemPackages = with pkgs; [
  vim
  git
  curl
];

# User packages
home.packages = with pkgs; [
  ripgrep
  fd
  bat
];
```

### Program Configuration

```nix
programs = {
  zsh = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
    };
  };

  starship = {
    enable = true;
    settings = { ... };
  };
};
```

### Service Configuration

```nix
systemd.user.services = {
  my-service = {
    Unit = { ... };
    Service = { ... };
    Install = { ... };
  };
};
```

## Module Organization

### Directory Structure

```text
modules/
├── darwin/              # System-level configuration
│   ├── default.nix      # Main system config
│   ├── homebrew.nix     # Homebrew packages
│   ├── fonts.nix        # Font configuration
│   └── auto-update.nix  # Auto-update service
└── home/                # User-level configuration
    ├── default.nix      # Main user config
    ├── 1password-agent.nix # 1Password SSH agent
    ├── ai/              # AI configuration (claude, hermes, opencode, skills)
    ├── aerospace.nix    # Aerospace window manager
    ├── fastfetch.nix    # System info display
    ├── ghostty.nix      # Ghostty terminal emulator
    ├── git.nix          # Git configuration
    ├── nodejs.nix       # Node.js development
    ├── nixvim.nix       # Nixvim module (disabled)
    ├── python.nix       # Python development
    ├── starship/        # Starship prompt config
    ├── zed/             # Zed editor settings and keybindings
    └── zellij.nix       # Zellij terminal multiplexer
```

### Module Creation Guidelines

1. Each module should be self-contained
2. Use imports for composition over inheritance
3. Provide sensible defaults
4. Document complex configurations
5. Handle missing dependencies gracefully

## Hostnames

The configuration targets a specific Darwin host. The default host is `endor` (set in `justfile`).

```bash
# Build for the default host (endor)
nh darwin build

# Override the hostname explicitly
nh darwin switch -- --flake .#endor
nix build .#darwinConfigurations.endor.system
```

## Development Workflow

### Making Changes

1. Edit configuration files
2. Run `git add` for any **new files** — Nix flakes can only resolve git-tracked files
3. Run `just fmt` to format Nix files (required before committing)
4. Run `just check` to validate changes
5. Check if documentation (README.md, AGENTS.md) needs updating to reflect the changes — especially when adding/removing modules, changing workflows, updating commands, or making architectural changes (new services, hosts, infrastructure). When in doubt, update the README.
6. Build with `nh darwin build` (user must run `just switch` to activate)

### Committing

- **Scope commits precisely.** Only stage files that are part of the current session's changes — never stage unrelated pending work from the working tree. Use `git diff --name-only` to verify you're only committing what was just discussed or modified.
- **Pre-commit hooks run on all staged files.** If an unrelated file has a hook failure (e.g. deadnix unused variable), the entire commit is blocked. Check `git diff --cached` for other staged changes and either fix or unstage them before committing.
- After a failed commit, pre-commit stashes unstaged files and restores them. The commit is not created — fix the issue and retry.

> **Important:** Always run `just fmt` after editing Nix files. The pre-commit hooks will fail without proper formatting.

### Building for Remote NixOS Hosts

**Cannot build aarch64-linux on aarch64-darwin natively.** NixOS configurations
target Linux — building from a Darwin machine will fail with
`required system or feature not available: 'aarch64-linux'`. To deploy to a
remote NixOS host (e.g., coruscant RPi):

```bash
# Option 1: rsync the flake and build remotely
rsync -avz --exclude '.git/' --exclude 'result*' . root@<host>:/tmp/nixos-config
ssh root@<host> "cd /tmp/nixos-config && nixos-rebuild switch --flake .#<hostname>"

# Option 2: nixos-rebuild via nix run (if nixos-rebuild not locally installed)
# Requires a Linux builder or building on the target host

# Option 3: Use just nixos-deploy (hostname configured in justfile)
just nixos-deploy              # deploys to default host (coruscant)
just nixos-deploy-ip 10.0.0.2 # deploys to specific IP
```

Evaluation can still be verified locally: `nix eval .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath`

### Adding New Packages

- System packages: Add to `modules/darwin/default.nix`
- User packages: Add to `modules/home/default.nix`
- Homebrew: Add to `modules/darwin/homebrew.nix`
- Consider creating separate modules for complex configurations

### Updating Dependencies

- Run `just update` to update all flake inputs
- Use `just update-input nixpkgs` for specific updates
- Test thoroughly after updates

### SD Image CI / GitHub Actions

The `build-sd-image.yml` workflow builds an aarch64-linux SD image on
`ubuntu-latest` using QEMU emulation. Key lessons:

- **Must `git push` before triggering**: `gh workflow run --ref main`
  uses whatever is on the remote `main` — local commits don't count.
- **Disable FlakeHub**: `nix-installer-action` defaults to FlakeHub
  which requires OIDC auth. Set `flakehub: false`.
- **No magic-nix-cache**: That action also requires FlakeHub auth and
  rate-limits easily. Remove it for infrequent builds.
- **Cross-arch builds need config**: For `--system aarch64-linux` on
  `x86_64-linux` via QEMU, set `extra-platforms = aarch64-linux` and
  `sandbox = false` (or mount `/run/binfmt` into sandboxes).

## Special Considerations

### Nixvim Module

- Currently disabled due to Swift build dependency issues
- To enable: uncomment `./nixvim.nix` in `modules/home/default.nix`
- Consider binary cache if enabling

### Determinate Nix

- Using Determinate Nix installer instead of nix-darwin's Nix
- Nix settings configured via `~/.config/nix/nix.conf`
- Binary cache configured for llm-agents

### Work SSH Configuration

- Supports separate SSH keys for work/personal repos
- Work repos in `~/Projects/work/` use work SSH key automatically
- Configuration files not tracked in git for security

## Pre-commit Integration

- Comprehensive hook suite configured in `flake-parts/pre-commit.nix`
- Uses `prek` as pre-commit implementation
- Hooks run on `git commit` after installing via `pre-commit install`

## Research Tools

### grep-mcp_searchGitHub (MCP)

Use this tool to search real-world code examples from millions of public GitHub repositories. This is particularly useful for:

- Finding correct usage patterns for libraries, frameworks, and tools
- Understanding how to configure tools like Zed, Neovim, etc.
- Discovering correct CLI arguments and flags for external formatters/linters

**When to use grep-mcp_searchGitHub:**

- When the user describes a problem with external tools (Zed, Neovim plugins, linters, formatters)
- When you need to look up correct configuration syntax for a tool
- When NixOS/nix documentation doesn't cover the specific use case
- When you need real-world examples of how others solved similar problems
- **Crucial for Nix:** Because Nix documentation can be fragmented, always use the `language: ["Nix"]` filter when looking for how to configure a specific package or option in a flake/home-manager setup.

**Examples:**

```text
# Find how others configure a specific Neovim plugin in Nix
# (Ensure you pass the language filter: language=["Nix"])
setupOpts = {

# Find how others configure Python formatters in Zed
# (query for actual code patterns, not questions)
ruff format --stdin-filename

# Find correct prettier arguments with buffer_path
prettier --stdin-filepath

# Find how others use specific Zed settings
formatter.external
```

**Note:** Search for actual code that would appear in files, not keywords or questions.

## Debugging Tips

### Build Issues

- Use `nix build .#darwinConfigurations.<hostname>.system` for detailed errors
- Check `/var/log/system.log` for nix-darwin issues
- Use `nh darwin generations` to view history

### Configuration Validation

- Run `just check` to validate config

### Common Problems

- Swift build timeouts: Disable nixvim or use binary cache
- Path issues: Ensure `/run/current-system/sw/bin` in PATH
- Permission issues: Use `sudo` for system-level changes
- HA `extraPackages` is a **function** (`_: []`), not a bare list (`[]`)
- HA `extraComponents` only includes integrations with Python deps —
  verify entries against the actual nixpkgs component list before adding

## Resources

- [nix-darwin documentation](https://github.com/LnL7/nix-darwin)
- [home-manager manual](https://nix-community.github.io/home-manager/)
- [Nixpkgs search](https://search.nixos.org/packages)
- [Nix language guide](https://nix.dev/manual/nix/stable/language/)
