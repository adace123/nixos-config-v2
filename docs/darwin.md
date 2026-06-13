# macOS / nix-darwin

This document covers setting up and maintaining the macOS (Darwin) configuration.

## Overview

The Darwin host (`endor`) is an Apple Silicon Mac managed by
[nix-darwin](https://github.com/LnL7/nix-darwin) and
[home-manager](https://nix-community.github.io/home-manager/). The configuration
lives under:

```text
flake-parts/darwin.nix          # host entry point (hostname, username, system)
modules/darwin/                 # system-level nix-darwin modules
modules/home/                   # home-manager user modules
```

## Prerequisites

1. **Install Nix** (Determinate installer recommended):

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L \
     https://install.determinate.systems/nix | sh -s -- install
   ```

2. **Install Homebrew** (required for GUI apps / Mac App Store):

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

## First-time Setup

Run the bootstrap script from the repo root:

```bash
./bootstrap.sh
```

Or manually:

```bash
# Install just (if not available yet)
nix profile install nixpkgs#just

# Build and activate
just switch HOST=endor
```

On a truly fresh machine where `darwin-rebuild` is not yet available:

```bash
nix build .#darwinConfigurations.endor.system
./result/sw/bin/darwin-rebuild switch --flake .
```

## Day-to-Day Usage

| Task | Command |
|------|---------|
| Apply config changes | `just switch` |
| Preview changes (dry-run) | `just build` |
| Validate (flake check + build) | `just check` |
| Update all flake inputs | `just update` |
| Update a single input | `just update-input nixpkgs` |
| Rollback to previous generation | `just rollback` |
| List generations | `just generations` |
| Garbage-collect old generations | `just clean` |

The shell alias `update` (configured in home-manager) is a shortcut for
`just switch`.

## Adding Packages

### System packages (available to all users)

Add to `environment.systemPackages` in `modules/darwin/default.nix`.

### User packages (home-manager)

Add to `home.packages` in `modules/home/default.nix`.

### Homebrew

Edit `modules/darwin/homebrew.nix`:

- **CLI tools** → `brews` list
- **GUI apps** → `casks` list
- **Mac App Store** → `masApps` attribute set (needs numeric app ID from
  `mas search "App Name"`)

## Customising the Host

Machine-specific values are currently set directly in `flake-parts/darwin.nix`
(username `aaron`, system `aarch64-darwin`) and `modules/darwin/default.nix`
(username reference, `primaryUser`).

> **Future goal:** Move these per-host values into a `hosts/endor/` directory so
> that adding a new machine is a copy-paste operation rather than editing shared
> files. See the architecture overview in `README.md` for the intended layout.

## Key Files

| File | Purpose |
|------|---------|
| `flake-parts/darwin.nix` | Host definition: system, username, home-manager wiring |
| `modules/darwin/default.nix` | System packages, macOS defaults, Touch ID sudo |
| `modules/darwin/homebrew.nix` | Homebrew formulae, casks, and MAS apps |
| `modules/darwin/fonts.nix` | Nerd Font packages |
| `modules/darwin/auto-update.nix` | Daily update-check launchd service |
| `modules/home/default.nix` | Shell, packages, Zsh, Starship, environment variables |
| `modules/home/git.nix` | Git config, signing, aliases |
| `modules/home/nvf/` | Neovim (nvf) with LSP/Treesitter |
| `modules/home/zed/` | Zed editor settings and keybindings |
| `modules/home/ai/` | Claude, Hermes, opencode CLI configurations |

## Troubleshooting

### `nh: command not found`

Reload your shell or run `just switch` first to install the package.

### Nix daemon issues

```bash
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

### Home-manager file conflicts

Back up and remove conflicting dotfiles, then re-run `just switch`.

### Touch ID not working in tmux

The `security.pam.services.sudo_local.reattach = true` setting handles this.
If it stops working after an OS update, run `just switch` to re-apply.

### Swift build timeouts (Nixvim)

Nixvim is disabled by default to avoid this. To enable it, uncomment
`./nixvim.nix` in `modules/home/default.nix` and accept the long build time or
point at a binary cache.
