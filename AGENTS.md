# AGENTS.md - Guidelines for Agentic Coding Agents

This file contains guidelines, commands, and conventions for agentic coding agents working in this NixOS/nix-darwin configuration repository.

## Repository Overview

This is a Nix flake-based configuration for managing macOS systems using nix-darwin and home-manager. The configuration includes system packages, user environment, development tools, and optional modules.

## Build/Test/Lint Commands

### Primary Commands

- `just check` - Run all checks (flake check, format, lint, pre-commit)
- `nix flake check --all-systems` - Check flake for errors across all systems
- `nh darwin switch` - Build and activate configuration (using nh helper)
- `nh darwin build` - Build without activating (using nh helper)
- `nh clean` - Enhanced garbage collection with better UX
- `nh search <pkg>` - Fast package search via Elasticsearch

### Formatting Commands

- `nixpkgs-fmt **/*.nix` - Format all Nix files
- `just fmt` - Format Nix files via justfile

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
    
    # External inputs
    inputs.nvf.homeManagerModules.default
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

## Module Organization

### Directory Structure

```text
modules/
├── darwin/           # System-level configuration
│   ├── default.nix   # Main system config
│   ├── homebrew.nix  # Homebrew packages
│   ├── fonts.nix     # Font configuration
│   └── auto-update.nix # Auto-update service
└── home/             # User-level configuration
    ├── default.nix   # Main user config
    ├── python.nix    # Python development
    ├── nodejs.nix    # Node.js development
    ├── git.nix       # Git configuration
    └── nvf/          # Neovim configuration
```

### Module Creation Guidelines

1. Each module should be self-contained
2. Use imports for composition over inheritance
3. Provide sensible defaults
4. Document complex configurations
5. Handle missing dependencies gracefully

## Development Workflow

### Making Changes

1. Edit configuration files
2. Run `just fmt` to format Nix files
3. Run `just check` to validate changes
4. Test with `nh darwin build`
5. Apply with `nh darwin switch`

### Adding New Packages

- System packages: Add to `modules/darwin/default.nix`
- User packages: Add to `modules/home/default.nix`
- Homebrew: Add to `modules/darwin/homebrew.nix`
- Consider creating separate modules for complex configurations

### Updating Dependencies

- Run `just update` to update all flake inputs
- Use `just update-input nixpkgs` for specific updates
- Test thoroughly after updates

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

### Pre-commit Integration

- Comprehensive hook suite configured in `flake-parts/pre-commit.nix`
- Uses `prek` as pre-commit implementation
- Hooks automatically run in development shell

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

## Debugging Tips

### Build Issues

- Use `nix build .#darwinConfigurations.<hostname>.system` for detailed errors
- Check `/var/log/system.log` for nix-darwin issues
- Use `nh darwin generations` to view history

### Configuration Validation

- Run `nix flake show` to inspect outputs
- Use `nix flake metadata` to check inputs
- Test with `nh darwin build` before switching

### Common Problems

- Swift build timeouts: Disable nixvim or use binary cache
- Path issues: Ensure `/run/current-system/sw/bin` in PATH
- Permission issues: Use `sudo` for system-level changes

## Resources

- [nix-darwin documentation](https://github.com/LnL7/nix-darwin)
- [home-manager manual](https://nix-community.github.io/home-manager/)
- [Nixpkgs search](https://search.nixos.org/packages)
- [Nix language guide](https://nixos.org/manual/nix/stable/language/)
