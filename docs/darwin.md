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

`just switch` sends a macOS notification when activation needs sudo auth
(Touch ID or a YubiKey touch), so you know to act when the prompt appears.
When the lid is closed it also blocks until a YubiKey is plugged in. The
YubiKey hook needs `~/.config/Yubico/u2f_keys` (see
`scripts/setup-yubikey-sudo.sh`); see `scripts/yubikey-sudo-shim.sh`.

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

Hand-installed binaries dropped into `~/.local/bin` (for example `cliamp`, the
terminal music player installed from its own release) still need their Homebrew
runtime libraries listed in `brews`: `cleanup = "zap"` uninstalls anything not
declared there on the next activation, and a binary that links
`/opt/homebrew/opt/<lib>/lib/...` aborts with `dyld: Library not loaded` once
that library is gone.

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
- **OmniWM** (`omniwm.nix`) — tiling window manager, replacing AeroSpace; see
  [Window Management](#window-management).
- **Ghostty** (`ghostty.nix`) — GPU terminal with a Tokyo Night color scheme
  and FiraCode Nerd Font.
- **Dev toolchains** — `nodejs.nix` (Bun default + Node 22/20, TS tooling),
  `python.nix` (Python 3.14 + uv, ruff, mypy), `packages.nix` (ripgrep, fd,
  bat, eza, fzf, direnv, nh, lazygit, … — see the file for the full list).
  The generated `~/.npmrc` deliberately omits `prefer-offline` so npm
  revalidates registry metadata instead of serving stale packuments (the
  `ETARGET` failure this caused is described in [docs/ai.md](ai.md)).
- **Ollama** (`ollama.nix`) — local LLM server as a per-user launchd agent on
  `127.0.0.1:11434`; see [Ollama](#ollama).
- **fastfetch** (`fastfetch.nix`) — `fastfetch` replaces `neofetch`, with a
  clean JSON config.

See also [docs/ai.md](ai.md) for the AI agents (Claude, Pi, Hermes, Herdr)
that run in this shell.

## Ollama

`modules/home/ollama.nix` runs [Ollama](https://ollama.com) as a local LLM
server on this Mac:

```shell
ollama pull qwen3:8b           # models live in ~/.ollama
curl http://127.0.0.1:11434    # "Ollama is running"
```

It uses home-manager's `services.ollama`, which on Darwin installs a per-user
launchd agent — `~/Library/LaunchAgents/org.nix-community.home.ollama.plist`,
loaded into the `gui` domain and wrapped in `wait4path /nix/store` so it does
not race the store mount at login. The module adds `RunAtLoad` and log paths
`~/Library/Logs/ollama.log` on top; the server restarts itself if it crashes.
The `ollama` package comes from nixpkgs (flake-pinned, Metal-accelerated on
Apple Silicon) rather than Homebrew or the official `.app`.

Key properties:

- **Localhost only.** `OLLAMA_HOST=127.0.0.1:11434`. Ollama has no
  authentication, so binding `0.0.0.0` would give every host on the LAN
  unrestricted use of this Mac's GPU. Change `host` in the module if that is
  ever wanted deliberately.
- **Offline-capable, self-contained.** Nothing here downloads models; pull them
  by hand. To point models elsewhere, set `OLLAMA_MODELS` via
  `services.ollama.environmentVariables`.
- **LM Studio was removed** once Ollama took over the local-LLM role —
  `cleanup = "zap"` in `modules/darwin/homebrew.nix` uninstalls it on the next
  switch.

Troubleshooting:

Look for the `inference compute` line in the log on the first model load —
`library=Metal` confirms the GPU backend loaded. That is the expected result on
Apple Silicon: the nixpkgs build links `Metal.framework`/`MetalKit.framework`
and embeds the ggml Metal backend (no separate `.metallib` file).

```shell
# agent state
launchctl print gui/$(id -u)/org.nix-community.home.ollama

# restart
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.ollama

# server logs
tail -f ~/Library/Logs/ollama.log
```

## DNS

`modules/darwin/dns.nix` points every enabled network service at Cloudflare's
resolvers (`1.1.1.1`, `1.0.0.1`) at activation — macOS stores DNS per service, so
the script walks them rather than setting it globally.

It coexists with Tailscale instead of replacing it: Tailscale answers tailnet names
itself (`dathomir-1`, `*.ts.net`, …) and forwards everything else to the service's
resolver, so Cloudflare is what reaches the public internet.

Applied by `just switch`; there is nothing else to run.

## Window Management

OmniWM (`modules/home/omniwm.nix`) is the tiling window manager: Niri-style
scrolling columns, ten workspaces named `1`–`10` mostly assigned to the main
display, and Option-based bindings in the shape of the AeroSpace config it
replaced (`Option+H/J/K/L` to focus, `Option+Shift+…` to move, `Option+1`–`0`
for workspaces, `Option+[` / `Option+]` to step through them, `Option+Q` to
close the focused window, `Option+S` for the command palette). Its `appRules` put
browsers, terminals, editors, chat and media on their own workspaces and float
Finder, 1Password, System Settings and Activity Monitor.

The workspace bar rides in the macOS menu-bar strip. `notchMode =
"splitActiveLeft"` splits it around the notch with the active workspace docked
on its left, and `system.defaults.NSGlobalDomain._HIHideMenuBar` auto-hides
macOS's own bar so it is the only one up there — pushing the pointer to the top
edge still reveals the real menus. The packaged default, `moveBelowMenuBar`,
dodges the notch by dropping the island onto a second row instead, which is what
stacked two bars on the built-in display.

The module imports `inputs.omniwm.homeManagerModules.default` — **not** the
module home-manager ships. OmniWM rejects any `settings.toml` that is not its
complete schema, and the stock module writes exactly the attrset it is given, so
partial settings there are dropped silently at runtime. This one deep-merges the
declared settings over a full defaults file generated from the packaged version,
merges `hotkeys` per id, and fails evaluation on an action id the packaged
OmniWM does not know. See the `omniwm` input comment in `flake.nix`.

OmniWM is installed from that input rather than from nixpkgs because the
defaults file it merges over is generated from the version the input packages;
taking the binary from nixpkgs instead would pair one version's schema with
another version's binary.

`assignToWorkspace` only applies while an app has no tracked windows, so an
app's *second* window opens on whatever workspace was active — where AeroSpace's
`on-window-detected` rules applied to every window. The
`omniwm-app-workspaces` launchd agent closes that gap: it runs `omniwmctl watch
display-changed,windows-changed` over OmniWM's IPC socket
(`general.ipcEnabled`) and moves the windows that are in the wrong place. Dia
goes to the workspace the TV is showing while a display whose name contains
*TV* is connected, and back to workspace 1 when it is not; Ghostty always goes
to workspace 2. Everything else, and every window already where it belongs, is
left alone.

Each run also ends with `omniwmctl command rescue-offscreen-windows`. A display
that goes away — the lid closing, a monitor being unplugged — takes its
workspaces with it, and the windows on them stay alive with no display left to
draw them on: the app is running, its Dock icon activates it, and nothing
appears. The rescue returns the windows whose frames fell off every remaining
display. OmniWM answers `no_change` when there are none, so it costs one no-op
IPC call and never moves a window that was parked somewhere on purpose.
`Control+Option+Shift+R` runs the same rescue by hand.

That agent reconciles on every window change, so those two apps cannot be
parked on another workspace while it runs. It logs to
`~/Library/Logs/omniwm-app-workspaces.{log,err.log}`. OmniWM's IPC socket is a
same-user trust boundary — `0600` under
`~/Library/Application Support/com.barut.OmniWM/`, plus a random token — and
`omniwmctl` is its only client here.

Two consequences worth knowing:

- **Declared settings are owned by the module.** OmniWM rewrites
  `~/.config/omniwm/settings.toml` from its own GUI, and the module regenerates a
  writable copy whenever the declared values differ. GUI edits to a key set in
  `modules/home/omniwm.nix` do not survive a switch; edit the module instead.
- **Display-dependent keys are preserved, not committed.** `preserveSettings`
  lists `routing`, `monitors` and the `monitor*Overrides` tables, which are keyed
  by display UUID. Configure them once per desk with OmniWM's own Monitors
  settings; each activation carries the live values over into the regenerated
  file. `monitors.ranking` — the **Monitor Roles** order — is the one to get
  right: `workspaceSpecs` assigns eight workspaces to `main` and ❤️/🚀 to
  `secondary`, and those roles decide which monitor each workspace lands on.
  With no ranking, `main` is whatever macOS calls the main display and the rest
  follow arrangement order, so a virtual display sitting left of the physical
  monitor (Muse's, at `x=1728`) outranks it and inherits `main` the moment the
  built-in display disconnects on lid close — leaving the physical monitor on an
  empty workspace while the browser is drawn on a display nobody can see. Rank
  them built-in, then the monitor, then Muse.
- **A shortcut that types a character stops while Secure Input is on.** OmniWM
  pauses any shortcut whose key would type something unless the chord uses
  Control or Command, so a password field, 1Password or Ghostty's Secure
  Keyboard Entry takes `Option+[` / `Option+]` — and the `Option+H/J/K/L` focus
  and move keys, `Option+Q` and `Option+S` — with it. `Control`-based chords keep
  working.
- **Two actions on one chord are both dead.** OmniWM drops every action whose
  chord another action also claims, so the shared key does nothing rather than
  driving one of them. It ships `toggleWorkspaceLayout` on `Option+Shift+L`,
  which is `move.right` here; the toggle is `Unassigned` in the module for that
  reason. Its **Settings > Keyboard Shortcuts** window lists the actions it
  failed to register.
- **The first launch needs two permissions granted by hand.** OmniWM asks for
  Accessibility and Input Monitoring — both required at launch — plus optional
  Screen Recording (Overview thumbnails, drag previews) and Full Disk Access
  (Hidden Bar concealing). macOS keeps those in its own TCC database, so they
  cannot be declared here; grant them once from OmniWM's permissions window.

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
| `modules/home/omniwm.nix` | OmniWM tiling window manager |
| `modules/home/ghostty.nix` | Ghostty terminal |
| `modules/home/fastfetch.nix` | `fastfetch` config |
| `modules/home/nodejs.nix` | Bun/Node.js + TS tooling |
| `modules/home/python.nix` | Python 3.14 + uv |
| `modules/home/ollama.nix` | Ollama LLM server (per-user launchd agent) |
| `modules/home/git.nix` | Git config, signing, aliases |
| `modules/home/secrets.nix` | SOPS location for home secrets |
| `modules/home/nix.nix` | `~/.config/nix/nix.conf` (Determinate Nix) |
| `modules/home/1password-agent.nix` | 1Password SSH agent key mappings |
| `modules/home/nixvim/` | Neovim (nvf) with LSP/Treesitter |
| `modules/home/ai/` | AI agents — see [docs/ai.md](ai.md) |

### Disabled modules

| Directory | Status |
|-----------|--------|
| `modules/home/zed/` | Present but not imported — `./zed` is commented out in `modules/home/default.nix`, so Zed is configured by hand. The `zed-extensions` overlay (`flake-parts/darwin.nix`) and the `zed-extensions` input (`flake.nix`) remain so re-enabling is a one-line change. |

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
