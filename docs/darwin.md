# macOS / nix-darwin

This document covers setting up and maintaining the macOS (Darwin) configuration.

## Overview

The Darwin host (`endor`) is an Apple Silicon Mac managed by
[nix-darwin](https://github.com/LnL7/nix-darwin) and
[home-manager](https://nix-community.github.io/home-manager/). The configuration
lives under:

```text
hosts/endor/default.nix         # host identity (hostname, username, system)
flake-parts/darwin.nix          # darwin output wiring from host metadata
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

`bootstrap.sh` automates the first-time macOS setup: it installs Homebrew if
missing, verifies Nix is present (it prints the install command and exits if
not), detects your hostname, builds `.#darwinConfigurations.<hostname>.system`,
and activates it with `darwin-rebuild switch`. If nix-darwin is already
installed it just prints the rebuild/`just switch` instructions and exits.

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

Machine-specific identity values are defined in `hosts/endor/default.nix` and
consumed by shared wiring/modules (`flake-parts/darwin.nix`,
`modules/darwin/default.nix`). Adding another Darwin machine should follow the
same pattern: add host metadata, then reuse shared modules.

## Shell & CLI Environment

`modules/home/` configures the interactive shell and CLI tooling:

- **Zsh** (`zsh.nix`) — completions, autosuggestion, syntax highlighting, and
  agent aliases (`cc`, `oc`, …).
- **Starship** (`starship.nix`) — minimal cross-shell prompt (directory, git
  branch/status, nix shell).
- **AeroSpace** (`aerospace.nix`) — i3-style tiling window manager
  (`.aerospace.toml`, starts at login).
- **Ghostty** (`ghostty.nix`) — GPU terminal with a Tokyo Night color scheme
  and FiraCode Nerd Font.
- **Dev toolchains** — `nodejs.nix` (Bun default + Node 22/20, TS tooling),
  `python.nix` (Python 3.14 + uv, ruff, mypy), `packages.nix` (ripgrep, fd,
  bat, eza, fzf, direnv, nh, lazygit, … — see the file for the full list).
- **fastfetch** (`fastfetch.nix`) — `fastfetch` replaces `neofetch`, with a
  clean JSON config.

See also [docs/ai.md](ai.md) for the AI agents (Claude, OpenCode, Pi, Hermes,
Herdr) that run in this shell.

## Key Files

| File | Purpose |
|------|---------|
| `hosts/endor/default.nix` | Host identity data (hostname, user, system) |
| `flake-parts/darwin.nix` | Darwin output wiring from host metadata |
| `modules/darwin/default.nix` | System packages, macOS defaults, Touch ID sudo |
| `modules/darwin/homebrew.nix` | Homebrew formulae, casks, and MAS apps |
| `modules/darwin/fonts.nix` | Nerd Font packages |
| `modules/darwin/auto-update.nix` | Daily update-check launchd service |
| `modules/home/` | User-level modules (see `default.nix` for the import list) |
| `modules/home/base.nix` | User identity, PATH, session variables (EDITOR, NH_FLAKE) |
| `modules/home/packages.nix` | CLI tools and dev utilities |
| `modules/home/zsh.nix` | Zsh shell config + aliases |
| `modules/home/starship.nix` | Starship prompt |
| `modules/home/aerospace.nix` | AeroSpace tiling window manager |
| `modules/home/ghostty.nix` | Ghostty terminal |
| `modules/home/fastfetch.nix` | `fastfetch` config |
| `modules/home/nodejs.nix` | Bun/Node.js + TS tooling |
| `modules/home/python.nix` | Python 3.14 + uv |
| `modules/home/git.nix` | Git config, signing, aliases |
| `modules/home/secrets.nix` | SOPS location for home secrets |
| `modules/home/nix.nix` | `~/.config/nix/nix.conf` (Determinate Nix) |
| `modules/home/1password-agent.nix` | 1Password SSH agent key mappings |
| `modules/home/nixvim/` | Neovim (nvf) with LSP/Treesitter |
| `modules/home/zed/` | Zed editor settings and keybindings |
| `modules/home/ai/` | AI agents — see [docs/ai.md](ai.md) |

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
