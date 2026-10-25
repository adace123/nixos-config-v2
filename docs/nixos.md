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
`RuntimeWatchdogSec=10s` means a frozen kernel reboots itself rather than hanging
until power is pulled. `RebootWatchdogSec` is explicitly `0`, not unset: leaving
it unset does **not** disable it — systemd's default is 10 minutes, which the chip
cannot hold, so it is silently ignored and only looks like protection. Any value
the chip can actually hold (it tops out near 15 s) would hard-reset the board
mid-shutdown while podman is still stopping Home Assistant.

## Storage hardening on the USB root

A systemd runtime watchdog only fires when PID 1 stops petting it, so it does *not*
cover the failure the Pi hosts actually had on 2026-10-23: PID 1 stayed alive and
logged `Failed to spawn … Input/output error` while the root device silently stopped
accepting writes — three store paths ended up 0-byte yet still registered as valid in
the Nix database. `modules/nixos/rpi-boot.nix` therefore adds:

- `usb-storage.quirks=0bda:9201:u` — the Ugreen/Realtek bridge's UAS driver is the
  flaky part; `u` keeps the device on the bulk-only driver. Safe because
  `CONFIG_USB_STORAGE=y` (builtin) while `CONFIG_USB_UAS=m`.
- `usbcore.autosuspend=-1` — no USB autosuspend on the root path.
- a udev rule forcing `cache_type="write through"` on `scsi_disk` devices, because
  the enclosure otherwise advertises a write-back cache with `FUA=0`, which is how
  an `fsync()` gets acknowledged and then lost on power cut.
- **`storage-canary.service`**: a `Type=notify` loop that fork-execs, writes and
  fsyncs a probe file, and only then pets systemd, with `FailureAction=reboot-force`
  — `reboot-force` calls `reboot(2)` directly, so it still works when forking is
  broken. Its watchdog is 5 minutes and probe failures inside the first 5 minutes of
  uptime do not reboot, so a machine that is already broken at boot cannot
  reboot-loop faster than you can log in and stop the unit.

If a deploy leaves the box unbootable, the previous generation is still on the boot
partition: point `os_prefix` in `config.txt` at it from any machine (see
[Troubleshooting](#troubleshooting)).

## Health monitoring

Two units cover the failures that used to be invisible on the Pi hosts.

**SMART** (`modules/nixos/ssd.nix`, SSD hosts only): `smartd` watches `/dev/sda`
with `-d sat`, because the 870 EVO hangs off a USB-SATA bridge and needs the SAT
translation layer. A short self-test runs daily at 02:00 and a long one on Sundays
at 04:00; warnings and failures go to the journal — no mail target is configured,
so the journal is the only place to look. If the bridge ever rejects SAT, try
`-d sat,12` before falling back to `-d auto`. The device is listed explicitly
(`autodetect = false`), so if it ever stops being `/dev/sda` the unit fails at
start instead of silently monitoring nothing: `systemctl status smartd`.

`smartd` is the on-host half. The beszel agent turns on `smartmon.enable`
wherever `services.smartd.enable` is set (`modules/nixos/beszel-agent.nix`), so the
same drive's attributes and health also reach the hub — and since Beszel notifies
on a SMART failure by itself, a failing drive reaches your phone with no alert rule
to write. That is the reason the agent gets `CAP_SYS_RAWIO` and the `disk` group on
these hosts and gives up `PrivateDevices`; where no SMART-managed disk exists it
keeps the tighter sandbox.

**Under-voltage** (`modules/nixos/rpi-boot.nix`, every Pi host):
`rpi-voltage-check.timer` polls `in0_lcrit_alarm` from `raspberrypi_hwmon` every
five minutes. `vcgencmd` cannot do this job here — it needs `/dev/vcio` from the
`bcm2835-vcio` driver, which this kernel does not build (the driver lives only in
Raspberry Pi's downstream tree). The poll sees the *current* alarm, not the
firmware's sticky "has throttled since boot" bit, so a dip that starts and ends
between two polls is missed: it is there to catch a marginal supply, not to time a
brownout.

While the alarm reads 1 the unit logs at `user.err` **and exits non-zero**, so it
enters `failed` rather than passing quietly — that is what turns a sagging supply
into a Beszel "Failed Services" notification instead of a journal line nobody
greps. The next run clears the unit once the supply recovers.

Two limits worth knowing about that alert path. Beszel re-reads the service list
every 10 minutes, and it ignores units with no `ActiveEnterTimestamp` — which is why
this oneshot is *not* listed between runs. A sustained sag keeps the unit failed, so
it is caught within one sweep; a dip that starts and ends between sweeps is not,
exactly like a dip that falls between the 5-minute polls. The check is a
marginal-supply detector, not a brownout recorder.

## Journal size

`modules/nixos/common.nix` caps the journal on **every** NixOS host:
`SystemMaxUse=512M` plus `SystemKeepFree=1G`, on top of `MaxRetentionSec=1month`.
Retention alone does not bound size — `coruscant`'s journal reached 2.1G in October
2026, mostly Home Assistant container stdout: the Alexa devices library retrying
Amazon per device, which logs as `aioamazondevices` and is why that logger is
pinned to `warning` in the HA config. With the cap in place the oldest entries are
dropped rather than the root filesystem filling up.

`journalctl --disk-usage` shows the size on disk. A spike is almost always one
unit logging per-request, which `journalctl --since -1h | cut -d' ' -f5 | sort |
uniq -c | sort -rn | head` narrows down before the cap hides the evidence.

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
| SMART (`smartd`) | — | `nixos/ssd.nix` |
| Under-voltage poll | — | `nixos/rpi-boot.nix` (`rpi-voltage-check`) |
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
| Boot SSD health | `smartctl -d sat -H /dev/sda` |
| Journal size on disk | `journalctl --disk-usage` |

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
