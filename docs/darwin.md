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

## macOS Defaults

`modules/home/macos-defaults.nix` holds per-user `defaults` overrides that
home-manager options cannot express. It currently disables ⌥⌘Space, the Finder
"Search This Mac" window.

macOS keeps that shortcut in the per-user `com.apple.symbolichotkeys` domain as
symbolic hotkey 65 (`parameters = (32, 49, 1572864)`), and it has no entry in
System Settings → Keyboard Shortcuts. An id *absent* from the domain means
"default, enabled", so the module writes the id with `enabled = false`. It
patches the exported domain with PlistBuddy rather than using
`defaults write -dict-add`, which cannot store nested composite types and
silently writes the old-style values as strings.

`WindowServer` only reads the domain when a login session starts, so a switch
takes effect at the next login, not in the current session.

## Shell & CLI Environment

`modules/home/` configures the interactive shell and CLI tooling:

- **Zsh** (`zsh.nix`) — completions, autosuggestion, syntax highlighting, and
  agent aliases (`cc`, `oc`, …). Its `.zshenv` also raises the soft file-descriptor
  limit to 65536: macOS starts a login session at 256, and Determinate Nix's
  tarball cache keeps a descriptor per cached pack, so `nix flake update` fails
  with `Too many open files` once that cache grows.
- **Nix** (`nix.nix`) — `~/.config/nix/nix.conf`, plus a
  `nix-tarball-cache-prune` launchd agent (every 6 h) that deletes
  `~/.cache/nix/tarball-cache-v2` once it holds more than 2000 pack files and
  clears the `pack_git2_*.lock` files interrupted fetches leave behind. The
  cache is a pure download cache, so a prune only costs a re-fetch; it logs to
  `~/Library/Logs/nix-tarball-cache-prune.log` and skips any run where a `nix`
  client is still active.
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
close the focused window, `Option+S` for the command palette, `Control+Option+B`
to hide and restore the workspace bar). Its `appRules` put
browsers on 1, the TV on 2, terminals on 3, chat on 4 and media on 5, and float
Finder, 1Password, System Settings and Activity Monitor.

The workspace bar rides in the macOS menu-bar strip. Since 0.8.0 it is drawn by
OmniShell, and the selected style's values win over the `workspaceBar` keys
described here — see [OmniShell, and the Herdr attention
widget](#omnishell-and-the-herdr-attention-widget); these remain the settings
for any key the style leaves unset. `notchMode = "splitActiveLeft"` splits it
around the notch with the active workspace docked on its left, and
`system.defaults.NSGlobalDomain._HIHideMenuBar` auto-hides macOS's own bar so it
is the only one up there — pushing the pointer to the top edge still reveals the
real menus. The packaged default, `moveBelowMenuBar`, dodges the notch by
dropping the island onto a second row instead, which is what stacked two bars on
the built-in display.

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
to workspace 3. Everything else, and every window already where it belongs, is
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

Workspace 2 is the TV workspace, `📺`. One is enough: the agent sends every Dia
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

### OmniShell, and the Herdr attention widget

**0.8.0 is pinned in the module, not in the input.** `inputs.omniwm` still
packages 0.7.6, and its module merges the declared settings over a
`settings-defaults.toml` generated from the version it packages, so bumping only
the binary would pair one version's schema with another's file. `omniwm.nix`
therefore swaps the release on the input's own packaging
(`overrideAttrs` with the v0.8.0 zip). What that costs until the input catches
up: the module keeps deploying the 0.7.6 schema (version 4), and 0.8.0 migrates
it to version 5 on launch — keeping `settings.toml.pre-v5` and adding the new
keys — so each activation rewrites the declared values and the next launch
migrates again. Values survive; only the migration bookkeeping repeats. Drop
the override once `inputs.omniwm` packages 0.8.0.

0.8.0 replaces the fixed workspace bar with **OmniShell**: the bar, panels,
popouts and islands are drawn by editable Luau widgets, and the selected style
supplies the look. A style's values win over the same `settings.workspaceBar`
keys, so the `workspaceBar` block in the module now only matters for keys the
style leaves unset — the bundled `Default` style is a 32 pt full-width bar over
the menu bar, pinned to 28 pt here. Change the look in **Settings > Styles &
Widgets**, not here, with one exception: the bar's theme, surface and the
per-widget options are pinned at activation.

`modules/home/omniwm/themes/omniwm-dark.toml` is a dark-only palette in the
shape of the sketchybar setup in
[sertdfyguhi/dotfiles](https://github.com/sertdfyguhi/dotfiles/blob/main/.config/sketchybar/sketchybarrc):
Catppuccin Mocha surfaces, lavender accents, a translucent base-coloured fill
and a hairline border. Both `[light]` and `[dark]` carry the same colours, so
the bar does not follow macOS back to a light palette; `barFill` uses 85%
opacity where the reference sketchybar uses ~40%, because an OmniShell palette
fill gets no compositor blur under it and the tint has to carry the depth.
`deploy-shell.nu` pins `theme` on the active profile and the bar keys the
bundled `Default` style pins ahead of both `settings.workspaceBar` and a theme's
`[workspaceBar]` — `backgroundOpacity`, `height` and `showItemBackgrounds` — in
`profiles.default.workspaceBar`, the one layer that wins. A GUI theme or bar
surface change therefore lasts until the next activation.

`modules/home/omniwm/shell-widgets.toml` carries the per-widget options, which
`deploy-shell.nu` merges into `profiles.default.widgets`: the centre
`active-window` widget is `icon_only` so the now-playing island is the only thing
that owns the middle of the bar; `battery-details` puts its percentage inside the
cell for a narrower trailing lane; and `workspaces` paints a background behind
occupied workspaces so the five pills show which have windows.

The now-playing player is `modules/home/omniwm/now-playing/init.luau`, deployed
to `~/.config/omniwm/shell/widgets/now-playing/` with one source for two
placements. `settings.island.enabled` in the module is the native master switch;
`deploy-shell.nu` merges the island root, display scope and 620 × 240 envelope
into `profiles.default.island`, drops the bundled `media` item from the trailing
lane (`--remove-widgets media`), and adds `now-playing` to the front of that lane
(`--trailing-widgets now-playing`).

On a **notchless display** — the external monitor — the island placement draws
the player. With a track the compact state is a fully rounded black pill inset
in the bar with the artwork, title and a native equaliser; nothing protrudes.
Hovering drops a 400 pt player out below the bar: artwork, title, artist, album,
a scrubber and a transport row of shuffle, previous, play/pause, next and
repeat. The play button is the one accent-filled control; the rest are quiet
circles that light up on hover, and shuffle/repeat take the accent when active.
A click pins the drop open, and Escape, a press outside or a click on the header
closes it.

On the **built-in notched display** the island placement renders nothing and the
trailing-lane placement takes over: a normal bar item with the artwork, title
and equaliser, whose click opens the bundled `media` popout (artwork, scrubber,
transport controls). The bar item hides itself on every other display, so the
two placements never appear together. Both draw nothing while no track is
playing.

Everything comes from the bundled `media` feed and actions. Nothing polls for
the equaliser — it is a native `loop` paint animation, paused with playback. The
island's `settings.toml` exposes **Drop the player on hover**, **Show the
artist** and **Show the album**.

AirPlay cannot be driven from the bar. The TV on this desk is an Amazon Fire TV
(mDNS `model=AFTTI43`) that advertises only the AirPlay **screen** service
(`_airplay._tcp`, port 7000) and no `_raop._tcp`, so macOS never creates an
AirPlay audio output for it — it can never appear in the Audio tab or the volume
popout, which list CoreAudio outputs. The video-and-audio cast is Apple's Screen
Mirroring in Control Center, and OmniShell's command surface has no entry for
it: `omniwm.run` parses only `volume`, `microphone`, `brightness`, `media`,
`calendar`, `reminders`, `notifications`, `input-source`, `wifi`, `bluetooth`,
`session`, `settings` panes, `toggle` and `trigger`, with no process launch or
AirPlay call. Cast from **Control Center → Screen Mirroring**, or drive that
menu with an Accessibility helper such as
[AirPlayControl](https://github.com/martinsoft/AirPlayControl) outside the
shell.

`modules/home/omniwm/battery-details/init.luau` shadows the `Default` style's
battery widget so the bar icon takes the theme's `accent` role — Catppuccin
mauve — instead of `foreground`: the outline, terminal nub and normal-state fill
are purple, the charging bolt is `accentForeground` so it stays legible on that
fill, and the warning red/amber fill still marks a low battery. Charging is the
one state the fill colour does not distinguish — both the normal and charging
tint are the accent — so the bolt is the tell: it sits inside the cell alone in
`beside`/`off` percent modes, and beside the percentage when the percentage is
inside the cell, where there is no room for it on its own. Charge level,
time remaining and the click-through popout stay on the style's shared
`lib/battery`, so only the cell is redrawn. It deploys to
`~/.config/omniwm/shell/widgets/battery-details/init.luau`, which OmniShell
resolves before the same-named widget in the style folder, and its
`require("../lib/…")` picks up the style's library folder.

The popout also lists the Bluetooth accessories' own batteries under a
"Bluetooth" heading above the settings row: a category icon, the device name
and category, its percentage and a mini cell, with the percentages repeated in
the bar item's tooltip. `modules/home/omniwm/bluetooth-battery.m` reads them
from IOKit's IOPS "Accessory Source" records — the ones `pmset -g accps` prints
and Control Center draws — because OmniWM's own `ctx.data.bluetooth` is gated on
a Bluetooth TCC grant that this machine has not given; only Bluetooth
transports are listed. That schema carries `Is Charging` as a boolean, so a row
gets an accent bolt (and "(charging)" in the tooltip) when the device reports
it; these two accessories do not, which is why the bolt is normally absent. The
`bluetooth-battery` launchd agent polls it, pushes the rows as
`bluetooth.batteries` (one `category<TAB>percent<TAB>charging<TAB>name` line per
device) over `omniwmctl shell set` every 30 seconds — runtime values live only
as long as OmniWM — and logs to
`~/Library/Logs/bluetooth-battery.{log,err.log}`.

`modules/home/omniwm/workspaces/init.luau` shadows the style's workspaces widget
and stops the bar at the first five workspaces. Ten stay configured — 6–10 are
overflow for extra windows and shortcuts — but the left side stays five pills
wide.

`modules/home/omniwm/weather/init.luau` shadows the style's weather widget and
draws the condition glyph in the theme's `cyan` role, matching the blue weather
icon in the reference sketchybar setup
([sertdfyguhi/dotfiles](https://github.com/sertdfyguhi/dotfiles/blob/main/.config/sketchybar/plugins/weather.sh)).
The location comes from `modules/home/omniwm/weather.toml` — the Home Assistant
coordinates in Los Angeles, in Fahrenheit — which `deploy-shell.nu` merges into
`profiles.default.weather`, and the widget sits at the end of the leading lane.
The forecast popout and `forecastHours` setting are the bundled widget's.

`modules/home/omniwm/tailscale/` is the Tailscale login-profile switcher. The
`tailscale-profiles` launchd agent polls `tailscale switch --list` and pushes
the current profile as runtime values (`tailscale.label`, `tailscale.state`,
`tailscale.profiles`, re-pushed every 15 seconds because they only live as long
as OmniWM). A bar widget cannot launch a process, so the agent also serves a
loopback bridge on `127.0.0.1:47832`: a popout row POSTs the profile id, the
agent re-reads the list, validates the id, and runs `tailscale switch <id>`.
While the request is in flight the bar item and the chosen row show a
quarter-circle spinner and "Switching…", cleared — or replaced by the failure —
when the reply arrives. The bar item itself is the real Tailscale mark (white
on transparent, rendered from the Simple Icons path; attribution beside the
PNG), copied into the widget folder at activation because `ui.image` refuses
paths that resolve outside it.

The widget's `settings.toml` declares `127.0.0.1` under
`[capabilities] network`; the module declares the matching approval in
`shellPermissions`, so the first switch does not wait on a prompt. That
declaration owns `shellPermissions.widgets`, so an approval the GUI adds for a
different widget has to be added to the module too or activation drops it. The
agent logs to `~/Library/Logs/tailscale-profiles.{log,err.log}`.

The `herdr-agents` widget (`modules/home/omniwm/herdr-agents/`) is a Herdr mark
in the bar followed by the number of agents in each status that is present
(blocked, done, working, idle, error — each with its dot, so `⚠ 2  ✓ 10  ▶ 1`),
and no title. A click opens its list, drawn like
Herdr's own sidebar — "Needs you", "Done" and "Working" groups in Herdr's own
priority order, each row the agent's mark and the workspace it runs in, all the
same width. Clicking a row brings Herdr to the front (`notifications open
dev.herdr.app`, the only host command that opens an app — Luau cannot run
`herdr-app do agent.focus`, which would need a native provider, and Herdr has no
URL scheme to deep-link into a pane). A per-user launchd agent (`herdr-agents`) polls
herdr-core's `hc ls --json` every 5 seconds and pushes one OmniShell runtime
value over `omniwmctl shell set`:

- `herdr.counts` — one `state=N` pair per status present, for the bar;
- `herdr.rows` — one `state<TAB>agent<TAB>space / tab` line per agent whose
  status is `working`, `blocked` or `done` (Herdr's "finished while nobody was
  looking", which becomes `idle` once the pane is viewed). The widget's list is
  built from these rows and nothing else.

Nothing is pushed when no agent needs a person. Runtime values live only as long
as OmniWM, so the agent re-pushes them every 30 seconds and a relaunched bar
fills in again. `hc` comes from herdr-core's own install in `~/.local/bin`; the
agent logs to `~/Library/Logs/herdr-agents.{log,err.log}`.

Its source is deployed read-only to `~/.config/omniwm/shell/widgets/herdr-agents/`;
the agent marks under `assets/` are **copied** there at activation instead of
linked, because OmniShell resolves an image path with `realpath` and silently
ignores anything that lands outside the widget folder — a store symlink renders
as nothing. The sources themselves are force-linked: home-manager only treats a
link that resolves into a `home-manager-files` generation as its own, so
without `force` a copy placed by hand — or left by an activation that predates
the file being listed here — stops the whole switch with "would be clobbered".

Placement is merged, not owned: OmniShell saves GUI layout changes into
`~/.config/omniwm/shell/shell.toml`, so `deploy-shell.nu` adds the positional
widget and the `--trailing-widgets` names to the active profile's `trailing`
lane (extras first) and removes `--remove-widgets` names from every lane, taking
each current lane from the profile override, else the profile folder's
`shell.toml`, else the bundled `default/` (or Default's lane before first
launch). It also merges the `--island` table into
`profiles.<profile>.island`. Everything else in the file is written back as it
was; a GUI edit that removes the widget or moves the island is undone at the next
activation. A lane is only written to the profile when this activation changes
it, so a lane it leaves alone keeps following the style. Once a lane has been
written, later changes to the style's own list do not reach it — delete that key
(or move the widget) to fall back to the style.

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
| `modules/home/macos-defaults.nix` | Per-user macOS `defaults` overrides (⌥⌘Space Finder search off) |
| `modules/home/packages.nix` | CLI tools and dev utilities |
| `modules/home/zsh.nix` | Zsh shell config + aliases |
| `modules/home/starship.nix` | Starship prompt |
| `modules/home/omniwm.nix` | OmniWM tiling window manager |
| `modules/home/ghostty.nix` | Ghostty terminal |
| `modules/home/fastfetch.nix` | `fastfetch` config |
| `modules/home/nodejs.nix` | Bun/Node.js + TS tooling |
| `modules/home/python.nix` | Python 3.14 + uv |
| `modules/home/ollama.nix` | Ollama LLM server (per-user launchd agent) |
| `modules/home/launchd.nix` | Unloads agents loaded from outside `~/Library/LaunchAgents` before activation |
| `modules/home/git.nix` | Git config, signing, aliases |
| `modules/home/secrets.nix` | SOPS location for home secrets |
| `modules/home/nix.nix` | `~/.config/nix/nix.conf` (Determinate Nix) |
| `modules/home/1password-agent.nix` | 1Password SSH agent key mappings |
| `modules/home/nixvim/` | Neovim (nvf) with LSP/Treesitter |
| `modules/home/ai/` | AI agents — see [docs/ai.md](ai.md) |

## Troubleshooting

### `nh: command not found`

Reload your shell or run `just switch` first to install the package.

### Nix daemon issues

```bash
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

### Launch agent fails with `I/O error (code 5)`

home-manager only unloads an agent whose plist it already installed in
`~/Library/LaunchAgents`. If the same label is loaded from somewhere else — a
manual `launchctl bootstrap` of a store plist while developing one, or a job left
over from an older experiment — activation's own bootstrap fails with
`Bootstrap failed: 5: Input/output error` and the switch aborts.
`modules/home/launchd.nix` unloads such jobs before `setupLaunchAgents` runs, so
the next switch recovers by itself. By hand:

```bash
launchctl bootout gui/$(id -u)/org.nix-community.home.<agent>
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
