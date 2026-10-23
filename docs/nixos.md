# NixOS / Raspberry Pi

This document covers provisioning and maintaining the NixOS host (`coruscant`),
a Raspberry Pi 4 running the home-server workload.

## Overview

The NixOS configuration lives under:

```text
hosts/coruscant/default.nix          # host identity (hostname, system)
flake-parts/nixos.nix                # NixOS output wiring from host metadata
modules/nixos/                       # host-specific modules
  common.nix                         # shared NixOS settings (SOPS, Tailscale)
  base.nix                           # hostname, SOPS, Tailscale auth
  home-assistant/                    # HA container + MQTT + Zigbee2MQTT + ESPHome
    default.nix                      # HA container, Mosquitto, Zigbee2MQTT, ESPHome
    restic.nix                       # Restic → R2 backups (see docs/backups.md)
    configuration.yaml               # Home Assistant base configuration template
  caddy.nix                          # Caddy reverse proxy (Cloudflare DNS)
  podman.nix                         # Podman engine + remote socket for the Mac
  beszel-agent.nix                   # Beszel monitoring agent (hub lives on dathomir)
  ssd.nix                            # Disko SSD partition layout + boot config
  sd.nix                             # SD-root storage (Turing Pi / TP2 nodes)
  rpi-boot.nix                       # Shared RPi kernel/boot settings
  installer.nix                      # Minimal SD-card installer image
```

## Hardware

- Raspberry Pi 4 (aarch64-linux)
- Boot device: USB SSD (recommended) or SD card
- Kernel: `pkgs.linuxPackages` (LTS), **not** `linuxPackages_latest` — see
  [Kernel and time](#kernel-and-time)
- Hostname: `coruscant`
- Network: Ethernet (DHCP) + optional WiFi

## Kernel and time

The Pi hosts are pinned to the LTS kernel (`modules/nixos/rpi-boot.nix`).
`linuxPackages_latest` was in use until October 2026, when `coruscant` began
hard-hanging with nothing in its journal — no panic, OOM, under-voltage or I/O
error — starting with the first boot on mainline 7.2.2, having run 7.1.8 for
weeks. If you bump the kernel, boot the host and leave it up for a few hours
before trusting it.

Because a Pi has no RTC, the clock comes up wrong on every boot and is corrected
by `chrony` (`modules/nixos/common.nix`, `makestep 1.0 3`). Until it is stepped,
TLS validation fails, so **Tailscale never joins the tailnet** and the host looks
dead remotely while its LAN interface is perfectly fine. When a NixOS host
appears unresponsive, always try its LAN address (`coruscant.local`) before
concluding it is down, and give a cold boot several minutes.

A hardware watchdog is enabled for the same reason: `bcm2835_wdt` plus
`RuntimeWatchdogSec`/`RebootWatchdogSec` means a frozen kernel reboots itself
rather than hanging until power is pulled.

## Services

| Service | Port | NixOS module |
|---------|------|--------------|
| Home Assistant | 8123 | `home-assistant/` (podman) |
| Mosquitto (MQTT) | 1883 | `home-assistant/` |
| Zigbee2MQTT | 8091 | `home-assistant/` |
| ESPHome | — | disabled — upstream removed the built-in dashboard, see `home-assistant/` |
| Beszel agent | 45876 | `nixos/beszel-agent.nix` (hub runs on dathomir) |
| Caddy (HTTPS proxy) | 443 | `caddy.nix` |
| Podman (container engine) | socket | `podman.nix` |
| Tailscale | — | `nixos/common.nix` |

## Initial Provisioning

### Option A — nixos-anywhere (recommended for SSD boot)

1. Build and flash the minimal installer SD image (see below).
2. Boot the Pi from the SD card; wait until it is reachable on the network.
3. Prepare the age key so secrets can be decrypted on the target:

   ```bash
   mkdir -p nixos-files/var/lib/sops-nix
   cp ~/.config/sops/age/host-keys/coruscant.txt nixos-files/var/lib/sops-nix/key.txt
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

## Podman

`modules/nixos/podman.nix` enables daemonless Podman as a Docker-compatible
container engine for the home-server workload. It exposes the rootful socket at
`/run/podman/podman.sock` (group-owned by `podman`, `dockerCompat` + symlinked
`/run/docker.sock` so docker CLI/compose work against it), and prunes images
weekly. The `nixos` user is in the `podman` group, so from the Mac you can drive
coruscant's containers remotely:

```bash
podman system connection add coruscant --identity ~/.ssh/<key> ssh://nixos@coruscant/run/podman/podman.sock
```

## Backups

Home Assistant data (`/var/lib/hass`) is backed up nightly to Cloudflare R2
with Restic (`home-assistant/restic.nix`). Snapshot listing, retention, restore,
and disaster recovery are covered in **[docs/backups.md](backups.md)**.

## Secrets on NixOS

The SOPS age key must be present at `/var/lib/sops-nix/key.txt` before NixOS
activates. The `just nixos-init` command copies it automatically via the
`nixos-files/` mechanism.

`nixos-files/` is a git-tracked directory that stages files onto a freshly
provisioned target during `nixos-init` (which uses `nixos-anywhere`). It
mirrors the target's filesystem read-only to place files that must exist
before first activation — primarily the decryption keys:

```text
nixos-files/
└── var/lib/
    ├── sops/age-key.txt      # staged key (sops-nix reads one of these two paths)
    └── sops-nix/key.txt      # staging path used by `just nixos-init`
```

Both paths are typically populated by copying that host's age key (one key per
host — see [docs/secrets.md](secrets.md)):

```bash
mkdir -p nixos-files/var/lib/sops-nix
cp ~/.config/sops/age/host-keys/coruscant.txt nixos-files/var/lib/sops-nix/key.txt
```

These are **private key files** — keep them out of public history. For an already
running host, copy the key manually if it is ever lost:

```bash
just install-sops-key coruscant root@coruscant.local
```

See [docs/secrets.md](secrets.md) for the full secrets workflow.

## Auto-upgrades

Automatic updates are **disabled** on all NixOS hosts (see
`modules/nixos/common.nix` for the rationale). Deploy changes intentionally by
running `just nixos-deploy` (or rsync the flake and run `nixos-rebuild switch`
manually). To re-enable, edit `modules/nixos/common.nix` and point
`system.autoUpgrade.flake` at a flake source the host can fetch directly
(e.g. `git+https://github.com/adace123/nixos-config-v2`).

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

### Zigbee devices drop off after a reboot

Check that `zigbee2mqtt` actually started, not just that systemd calls it active:

```bash
systemctl is-active zigbee2mqtt            # says "active" even when broken
journalctl -u zigbee2mqtt -b | grep -iE "Failed to init port|MQTT failed"
ss -ltn | grep 8091                        # the z2m frontend
```

Two races have bitten this unit, both leaving it `active` while the Zigbee network
is dead, and both are worked around in
`modules/nixos/home-assistant/default.nix`:

- `Failed to init port … Operation not permitted` — the nixpkgs module hardens the
  unit with `DevicePolicy=closed` plus `DeviceAllow=<the by-id path>`, and systemd
  resolves that path when it *loads* the unit, which at boot is before udev
  publishes `/dev/serial/by-id/…`. The device policy is overridden to `auto`.
- `MQTT failed to connect, exiting` — two independent causes, both fixed. The
  module only ordered the unit after `network.target`, so it could start before
  mosquitto and (unlike most services) it exits instead of retrying; it is now
  ordered after `mosquitto.service`. And the broker address was
  `mqtt://localhost:1883`, while `localhost` resolves to `::1` on these hosts and
  mosquitto listens on `listener 1883 127.0.0.1` — so it failed with
  `ECONNREFUSED ::1:1883` whenever the resolver picked IPv6. The address is now
  `mqtt://127.0.0.1:1883`.

A manual `systemctl restart zigbee2mqtt` fixes either in the meantime.

### Services restart by themselves minutes after boot

That is the clock step. The Pi hosts have no RTC, so they boot months in the past
and `chronyd` then steps the clock forward. systemd fires **every** calendar timer
whose elapse time went by during the jump, all at once — on coruscant
(2026-10-23) that meant nix-gc, `fstrim`, the Restic backup *and* its verification
job, `logrotate`, `podman-prune` and `podman-auto-update` starting together about
70 s into the boot, on a Pi 4. `podman auto-update` is what stopped Home Assistant
in that window: it stops the unit to replace the container, and here the container
came back only on a manual start. Expect transient service churn for a minute
around the step, and do not debug those services until `timedatectl` reads
correctly.
