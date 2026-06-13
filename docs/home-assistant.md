# Home Assistant

This document describes the current Home Assistant setup on `coruscant` and the
intended future structure.

## Current Layout

Home Assistant runs as a rootless Podman container managed by NixOS. The relevant
files are:

```text
modules/nixos/coruscant/
├── home-assistant.nix    # Container, MQTT, Zigbee2MQTT, ESPHome, user setup
└── configuration.yaml    # HA base config template (secrets injected by SOPS)
```

`home-assistant.nix` covers:

- **Podman container** (`ghcr.io/home-assistant/home-assistant:stable`)  
  Auto-starts, mounts `/var/lib/hass`, uses host networking for device discovery.
- **SOPS template rendering** — injects `time.timeZone` and
  `home-assistant-external-domain` into `configuration.yaml` before HA starts.
- **Mosquitto** MQTT broker (port 1883, localhost only).
- **Zigbee2MQTT** (port 8091, USB serial adapter `/dev/ttyUSB0`).
- **ESPHome** (port 6052).
- **Podman auto-update** — pulls newer images weekly.
- **`hass` system user** with `dialout`, `gpio`, `i2c` group membership.

Caddy provides HTTPS reverse-proxy access to HA on port 443 using Cloudflare
DNS-01 ACME (see `caddy.nix`).

## Secrets Required

| SOPS secret key | Used by |
|-----------------|---------|
| `home-assistant-external-domain` | `configuration.yaml` template, Caddy virtual host |
| `cloudflare-api-key` | Caddy DNS-01 challenge |

See [docs/secrets.md](secrets.md) for how to add or rotate secrets.

## Accessing Home Assistant

| Path | URL |
|------|-----|
| Local network | `http://coruscant.local:8123` |
| HTTPS (Tailscale or public) | `https://<home-assistant-external-domain>` |

## Zigbee2MQTT

The web UI is available at `http://coruscant.local:8091`. The Zigbee coordinator
is expected on `/dev/ttyUSB0` (Ember adapter). Change the `serial.port` and
`serial.adapter` settings in `home-assistant.nix` if using a different adapter.

## ESPHome

The dashboard is available at `http://coruscant.local:6052`.

## Monitoring Logs

```bash
just hass-logs                              # last 50 lines
just hass-logs LINES=200                    # last 200 lines
just hass-logs FILTER="error|recorder"      # filtered
```

---

## Intended Future Structure

The current single-file layout will become hard to navigate as the configuration
grows (automations, dashboards, custom scripts, Lovelace cards, etc.).

When the configuration outgrows a single file, restructure as follows:

```text
modules/nixos/coruscant/home-assistant/
├── default.nix           # Container, SOPS wiring, systemd services, user setup
├── mosquitto.nix         # Mosquitto MQTT broker
├── zigbee2mqtt.nix       # Zigbee2MQTT bridge
├── esphome.nix           # ESPHome dashboard
└── config/
    ├── configuration.yaml    # HA base config template
    ├── automations/          # One .yaml file per automation area
    │   ├── lighting.yaml
    │   ├── climate.yaml
    │   └── security.yaml
    ├── scripts/              # HA script definitions
    ├── dashboards/           # Lovelace dashboard YAML
    └── packages/             # HA package includes (grouping by domain)
```

**Trigger for restructuring:** when `home-assistant.nix` exceeds ~200 lines or
when you start maintaining more than a handful of automations. Until then,
keeping everything in one file is simpler.

**How to restructure:** split `home-assistant.nix` into the files above, update
the `imports` list in `base.nix`, and move `configuration.yaml` into
`config/configuration.yaml`. No Nix semantics change — it is a mechanical split.
