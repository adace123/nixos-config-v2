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
A switch therefore needs a terminal to prompt at all: run without one (an agent,
a launchd job), it exits before building rather than failing at sudo afterwards.

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

The same applies to a cask you installed by hand and want to keep: declare it in
`casks`, or cleanup uninstalls it on the next activation. A cask whose zap
stanza moves files to the Trash (rather than deleting them) fails that uninstall
with Homebrew's Full Disk Access error under activation's root context, which
aborts the switch instead of removing it — so an undeclared one keeps failing
every activation until it is declared or removed by hand.

A formula or cask from a non-official tap also has to be trusted: Homebrew
6.0.0 and later refuses to load it from an untrusted tap. Declare the tap in
`taps` with `trusted = true` (a bare `"user/repo"` defaults to untrusted), or
mark a fully-qualified `brews`/`casks` entry as trusted. `brew bundle cleanup`
rewrites the trust store from the Brewfile's `trusted:` entries before it
uninstalls anything, so a hand-run `brew trust` does not survive activation.

### USB Ethernet (ASIX AX88179)

The USB 3.0 gigabit dongle (ASIX `AX88179`, USB ID `0b95:1790`) needs a vendor
driver. The chip is USB **vendor-class** (`bDeviceClass 0xFF`), not
class-compliant, so macOS publishes the USB interface and then binds nothing to
it: no `en*` interface is created and the adapter is absent from Network
settings. That looks like a dead adapter but is a missing driver. The newer
`AX88179A` speaks native CDC-NCM and needs none of this.

Homebrew's `asix-ax88179` cask would install it, but is disabled upstream
(`disable! date: "2026-09-01", because: :fails_gatekeeper_check`). `brew`
refuses disabled casks, so listing it in `modules/darwin/homebrew.nix` would
fail adoption on every `just switch`. Use the script instead:

```bash
just setup-asix-ethernet                          # install
./scripts/setup-asix-ethernet.sh --uninstall      # remove
```

It downloads ASIX's 2.5.0 package, verifies a pinned SHA-256 before installing
anything, checks the package signature, then launches
`/Applications/ASIX_USB_Device_App.app` to register the extension.

That launch is not optional. The installer only drops
`com.asix.dext.usbdevice.dext` inside the app bundle, and a DriverKit extension
is invisible to System Settings until its host app submits an activation
request — without it the Driver Extensions panel stays empty and the driver
looks broken. After that, approve it in **System Settings → General → Login
Items & Extensions → Driver Extensions** and reboot. If it never appears there,
or the toggle is greyed out, this Mac is Jamf-managed and the approval is
policy-blocked — an IT request, not a local fix.

To see where it stands:

```bash
systemextensionsctl list | grep -i asix
# [activated waiting for user]  approval still pending in Settings
# [activated enabled]           done
```

Re-run after a major macOS upgrade, since the DriverKit extension can stop
loading. To tell a real adapter from a phantom, use
`networksetup -listallhardwareports`: a working adapter appears as an `en*`
with a burned-in MAC. The synthetic, sequentially allocated `e6:e9:8d:...`
addresses belong to macOS's placeholder "Ethernet Adapter" slots, which have no
hardware behind them.

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

## TLS trust store

`security.pki.caCertificateBlacklist` in `modules/darwin/default.nix` drops
roots from the bundle nix-darwin writes to `/etc/ssl/certs/ca-certificates.crt`,
which `NIX_SSL_CERT_FILE` points at. It distrusts `Comodo AAA Services root`, the
Sectigo cross-sign of the eight eMudhra/emSign intermediate CAs disclosed on
2026-10-17 — their private keys were recoverable from the public certificates,
so a forged certificate for any domain validated against them
(<https://emudhra.we-have-a-problem.com/>).

Entries are **NSS nicknames**, matched exactly — `Comodo AAA Services root`, not
the certificate's `CN=AAA Certificate Services`. A name that matches nothing
makes `buildcatrust` exit 3 with `Certs in blocklist but not in cert store` and
**fails the cacert build**, so any blacklisted root has to be one the pinned
Mozilla store still carries. NSS 3.131.1 removed the emSign G3/C1/C3 roots as
part of the same disclosure; nix-darwin's own `security.pki` module blacklists
those three only while `pkgs.cacert.version` is below 3.131.1, which is why this
list holds just the cross-sign. Drop an entry when an `nix flake update` brings
in a store that no longer contains it.

This bundle covers nix-built tools (`git`, `python3`, `curl`, `uv`). It does **not**
cover Apple's `/etc/ssl/cert.pem` (used by `/usr/bin/openssl` and `SSL_CERT_FILE`) or
Homebrew's `/opt/homebrew/opt/ca-certificates/share/ca-certificates/cacert.pem`;
those need the system bundle workaround or `brew upgrade ca-certificates`
respectively.

macOS's own trust evaluation, Safari and Chrome block the eMudhra intermediates
independently and need nothing. One exception is not fixable from here:
`/usr/bin/curl` is built `(SecureTransport)` and verifies through the system
keychain, so it ignores `--cacert`, `SSL_CERT_FILE` and `/etc/ssl/cert.pem` alike
— on this machine it still accepts a forged eMudhra chain, and only Apple can
change that. Test with the nix `curl`, not Apple's.

Verify a fix with the public checker — a certificate error means the client no
longer trusts the compromised intermediates:

```bash
curl https://dv-g3b-emudhra.we-have-a-problem.com/   # exit 60 = fixed
```

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

`reserveLayoutSpace = true` is what keeps windows out from under it. The bar
floats over the top of the display (`position = "overlappingMenuBar"`), inside
the strip macOS already reserves for its own (auto-hidden) menu bar: on the
built-in display `visibleFrame` stops below the 32pt notch band and the 24pt bar
sits in it, bottom-aligned to that edge. `workspaceBar.yOffset = 1` lifts the bar
1pt off it, which is the one point of background visible between the bar and the
window under it.

Nothing else carves that space out: `reserveLayoutSpace` only adds a row in
`belowMenuBar` mode, and `gaps.outer.top` is applied after the menu-bar band is
subtracted (`max(0, 10 − 32)` on the built-in display), so the side and bottom
gaps are the ones that show. `gaps.fullscreenUsesOuterGaps = true` gives a
fullscreen window the same outer gaps so it leaves the same strip, instead of
sitting at the display edge. That covers OmniWM's own fullscreen
(`Option+Return`). A real macOS fullscreen Space — the green button, or
`Ctrl+Cmd+F` — is composited above everything and cannot be worked around, which
is what `workspaceBar.hideInNativeFullscreen` is for: the bar steps aside
instead of being covered.

`workspaceBar.notchActiveZoneWidth = 60` — the floor the app clamps to — is what
keeps the split symmetric. The active island is centred inside a zone that wide
when it fits there, and its right edge lands on the 8pt notch gap when it does
not. At the packaged 180pt it was centred instead, and sat roughly 21pt from the
notch while the passive island sat 8pt from it.

`borders.width = 2.5` halves OmniWM's 5pt focus ring. It moves nothing: the ring
is drawn in the gap between windows, and every gap is already wider than either
width.

`singleWindowFit` is deliberately left at the default `"fill"`. A lone window
still keeps its 8pt side and bottom gaps, because `fullscreenUsesOuterGaps`
lands a fill window on the working frame those gaps were subtracted from, so one
window looks like several. The values OmniWM decodes there are only `"fill"`,
`"container_primary_span"` (Niri only) and an explicit `"WxH"` size — and a
value it does not decode makes it **ignore the entire settings file** and run on
its packaged defaults, which is how `"preserve"` turned the split notch bar back
into a second row below the notch and switched `ipcEnabled` off along with it.
The app says nothing about it; the rejection is only in the unified log:

```bash
log show --predicate 'subsystem == "com.barut.OmniWM"' --last 10m
```

`omniwmctl: ... No such file or directory` is the same failure seen from the
other side: with `ipcEnabled` back at its default `false`, the agent's socket is
not there at all.

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

The agent also handles the lid. Closing it migrates the work workspaces to the
external monitor, but that monitor comes back up on whichever workspace it was
last showing — usually the terminals — leaving the browser on a workspace nobody
is looking at. On a `display-changed` event with the lid closed, the agent
focuses the browsers' workspace, so the monitor shows the browser instead. The
gate is the event channel rather than the lid alone: a window event cannot
re-trigger it, and switching workspace afterwards stays where it is put.

Workspace 6 is the TV workspace, `📺`. One is enough: the agent sends every Dia
window to whatever workspace the TV is showing, and back to the browsers'
workspace when the TV goes. It is `tertiary`, which is what lands it on the TV —
the TV is deliberately left out of the Monitor Roles ranking so it sorts after
the built-in display and the monitor, taking the third role. The corollary is
that **ranking the TV would break it**: a ranked TV becomes secondary and pushes
the monitor to tertiary, so `📺` would then open on the monitor.

That role only holds on the full three-display desk. Roles are positional —
Main is the display with the macOS menu bar, Secondary and Tertiary the next two
in ranking order — so with the monitor away or the lid closed the TV sorts
second and takes `secondary`, `tertiary` is left without a display, and `📺`
falls back to the built-in: the TV is blank and the agent has no workspace to aim
Dia at. So the agent does not stop at reading the TV's workspace. When a TV is
connected and showing nothing, it force-moves `📺` there
(`omniwmctl workspace move-to-monitor … --force`) and re-reads the result before
reconciling. The direction is tried in turn — `up`, `right`, `down`, `left` —
because `move-to-monitor` walks the routing grid, not the display frames, and
which way the TV lies in that grid is preserved per desk rather than committed
here. `--force` overrides the assignment for that placement only; the settings
file keeps `tertiary`, so the next display change decides again.

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
  right: `workspaceSpecs` assigns nine workspaces to `main` and `📺` to
  `tertiary`, and those roles decide which monitor each workspace lands on.
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
| `modules/darwin/auto-update.nix` | Daily pull → build → switch launchd agent (see `docs/deployment.md#auto-updates`) |
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
