# NixOS / Raspberry Pi

This document covers provisioning and maintaining the NixOS host (`coruscant`),
a Raspberry Pi 4 running the home-server workload.

## Overview

The NixOS configuration lives under:

```text
hosts/coruscant/default.nix          # host identity (hostname, system)
flake-parts/nixos.nix                # NixOS output wiring from host metadata
modules/nixos/common.nix             # shared NixOS settings
modules/nixos/beszel.nix             # Beszel monitoring hub
modules/nixos/                  # host-specific modules
  base.nix                      # hostname, SOPS, Tailscale auth
  home-assistant/               # HA container + MQTT + Zigbee2MQTT + ESPHome
  caddy.nix                     # Caddy reverse proxy (Cloudflare DNS)
  ssd.nix                       # Disko SSD partition layout + boot config
  rpi-boot.nix                  # Shared RPi kernel/boot settings
  installer.nix                 # Minimal SD-card installer image
  configuration.yaml            # Home Assistant base configuration template
```

## Hardware

- Raspberry Pi 4 (aarch64-linux)
- Boot device: USB SSD (recommended) or SD card
- Hostname: `coruscant`
- Network: Ethernet (DHCP) + optional WiFi

## Services

| Service | Port | NixOS module |
|---------|------|--------------|
| Home Assistant | 8123 | `home-assistant/` (podman) |
| Mosquitto (MQTT) | 1883 | `home-assistant/` |
| Zigbee2MQTT | 8091 | `home-assistant/` |
| ESPHome | 6052 | `home-assistant/` |
| Beszel Hub | 8090 | `nixos/beszel.nix` |
| Caddy (HTTPS proxy) | 443 | `caddy.nix` |
| Tailscale | — | `nixos/common.nix` |

## Initial Provisioning

### Option A — nixos-anywhere (recommended for SSD boot)

1. Build and flash the minimal installer SD image (see below).
2. Boot the Pi from the SD card; wait until it is reachable on the network.
3. Prepare the age key so secrets can be decrypted on the target:

   ```bash
   mkdir -p nixos-files/var/lib/sops-nix
   cp ~/.config/sops/age/keys.txt nixos-files/var/lib/sops-nix/key.txt
   ```

4. Run the one-shot installer:

   ```bash
   just nixos-init
   # or with an explicit IP:
   just nixos-init 192.168.1.50
   ```

   This partitions the SSD with Disko, installs NixOS, copies the age key,
   and reboots into NixOS.

5. Remove the SD card before the next boot.

### Option B — direct nixos-rebuild (existing NixOS install)

If the Pi is already running NixOS:

```bash
just nixos-deploy
# or with an explicit IP:
just nixos-deploy 192.168.1.50
```

## Building the Installer SD Image

### Via GitHub Actions (native arm64 runner, no local cross-compilation needed)

```bash
just nixos-build-ci                    # build for the default host (coruscant)
NHOST=<host> just nixos-build-ci        # ...or another ARM host with a '-sd-image' variant
```

This triggers the `build-sd-image.yml` workflow, waits for it to finish, and
downloads the image to `result-sd-ci-<host>/` (e.g. `result-sd-ci-coruscant/`).
Then flash it:

```bash
just nixos-flash /dev/sdX
# or for a specific host:
NHOST=<host> just nixos-flash /dev/sdX
```

`nixos-flash` validates the whole-disk target, prompts before unmounting/overwriting,
and verifies the **full image** against the device after flashing. If a CI-built
image is older than the latest commit or `flake.lock`, it warns and defaults to
rebuilding locally.

You can also flash any pre-built image directly (official ISO, downloaded
`.img`, …) — compression (`.zst`/`.gz`/`.xz`) is detected automatically:

```bash
just nixos-flash /dev/sdX /path/to/image.img.zst
just nixos-flash /dev/sdX /path/to/nixos-minimal-aarch64.iso
```

Non-interactive use (CI, agents):

```bash
YES=1 just nixos-flash /dev/sdX
```

### Locally (requires aarch64-linux support)

```bash
nix build .#nixosConfigurations.coruscant-sd-image.config.system.build.sdImage
just nixos-flash /dev/sdX
```

## Turing Pi 2 nodes (`threepio`)

TP2 nodes are Raspberry Pi Compute Module 4 (aarch64, same SoC as the Pi 4).
`threepio` is the first one, booting from the SD card (see
`modules/nixos/sd.nix`). Because there is no separate SSD to install onto,
the `threepio-sd-image` config bakes the **production** configuration (unlike
`coruscant-sd-image`, which is a minimal installer):

```bash
NHOST=threepio just nixos-build-ci-flash /dev/sdX
```

The combined recipe builds the image on GitHub Actions, downloads it, then
flashes and verifies it locally. For the default host, use:

```bash
just nixos-build-ci-flash /dev/sdX
```

After first boot, copy the SOPS age key (see Secrets below), then deploy
updates with `NHOST=threepio just nixos-deploy`.

## Day-to-Day Operations

| Task | Command |
|------|---------|
| Deploy config changes | `just nixos-deploy` |
| Deploy to explicit IP | `just nixos-deploy <IP>` |
| View remote generations | `just nixos-generations` |
| Rollback remote host | `just nixos-rollback` |
| Tail Home Assistant logs | `just hass-logs` |
| Tail HA logs with filter | `just hass-logs FILTER="error\|recorder"` |

## WiFi Configuration

WiFi is disabled by default (Ethernet only). To enable it for a deployment:

```bash
WIFI_SSID=MyNetwork WIFI_PSK=supersecret just nixos-deploy
```

Or during initial install:

```bash
WIFI_SSID=MyNetwork WIFI_PSK=supersecret just nixos-init
```

## Tailscale Setup

Tailscale is enabled and uses a pre-auth key stored as a SOPS secret
(`ts-auth-key`). On first boot it will authenticate automatically if the key is
valid. To re-authenticate manually:

```bash
ssh root@coruscant.local
tailscale up
```

Once authenticated, SSH is available over Tailscale from anywhere:

```bash
ssh root@coruscant.<tailnet-name>.ts.net
```

## Secrets on NixOS

The SOPS age key must be present at `/var/lib/sops-nix/key.txt` before NixOS
activates. The `just nixos-init` command copies it automatically via the
`nixos-files/` mechanism. For an existing host, copy it manually if the key is
ever lost:

```bash
scp ~/.config/sops/age/keys.txt root@coruscant.local:/var/lib/sops-nix/key.txt
```

See [docs/secrets.md](secrets.md) for the full secrets workflow.

## Auto-upgrades

`system.autoUpgrade` is enabled in `modules/nixos/common.nix`. The host
automatically pulls and applies updates from the flake on `github:adace123/nixos-config-v2`.
To disable or adjust, edit `modules/nixos/common.nix`.

## Troubleshooting

### `nixos-anywhere` fails on kexec

kexec is not supported on Raspberry Pi. The `justfile` already passes
`--build-on remote` which skips kexec.

### SSD not detected after flash

Run `just nixos-verify-boot root@<target>` to check partition layout and
firmware configuration before rebooting.

### Home Assistant won't start

Check logs:

```bash
just hass-logs FILTER="error"
# or SSH in:
ssh root@coruscant.local
journalctl -u podman-home-assistant.service -f
```

Ensure `copy-hass-config.service` succeeded (it copies the SOPS-rendered
`configuration.yaml` before HA starts).

### Bluetooth not available in HA

`hardware.bluetooth.enable = true` is set in `base.nix`. If HA cannot see
Bluetooth, verify the USB Bluetooth adapter is present and the `dialout`/`gpio`
groups are assigned to the `hass` user.
