# Home Assistant

This document describes the current Home Assistant setup on `coruscant` and the
intended future structure.

## Current Layout

Home Assistant runs as a rootless Podman container managed by NixOS. The relevant
files are:

```text
modules/nixos/home-assistant/
├── default.nix           # Container, MQTT, Zigbee2MQTT, ESPHome, user setup
└── configuration.yaml    # HA base config template (secrets injected by SOPS)
```

`default.nix` covers:

- **Podman container** (`ghcr.io/home-assistant/home-assistant:stable`)  
  Auto-starts, mounts `/var/lib/hass`, uses host networking for device discovery.
- **SOPS template rendering** — injects `time.timeZone` and
  `home-assistant-external-domain` into `configuration.yaml` before HA starts.
- **Mosquitto** MQTT broker (port 1883, localhost only).
- **Zigbee2MQTT** (port 8091, Sonoff Zigbee dongle via stable
  `/dev/serial/by-id/...` path).
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
is expected at
`/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_9aff399ca0f3ef1187f6bb1b6d9880ab-if00-port0`
(Ember adapter). Change the `serial.port` and `serial.adapter` settings in
`default.nix` if using a different adapter.

Home Assistant sees Zigbee2MQTT through MQTT discovery as the
`Zigbee2MQTT Bridge` device; the physical USB dongle is owned by Zigbee2MQTT and
does not appear as a raw Home Assistant hardware device.

## ESPHome

The dashboard is available at `http://coruscant.local:6052`.

## Alexa Devices (TTS)

The official **Alexa Devices** integration (added in HA 2025.6) lets Home
Assistant send TTS announcements to Echo devices. It is built-in — no custom
components needed.

### Setup

1. In Home Assistant, go to **Settings > Devices & Services > Add Integration >
   **Alexa Devices**.
2. Enter your Amazon email and password.
3. Complete MFA using an authenticator app (required by Amazon).
4. Each Echo Dot appears as a `media_player` entity (e.g.
   `media_player.echo_dot_kitchen`).

### Sending TTS / Announcements

```yaml
# Text-to-speech via notify
service: notify.echo_dot_kitchen
data:
  message: "The laundry is done"
```

```yaml
# TTS via media_player
service: media_player.play_media
data:
  media_content_id: "The laundry is done"
  media_content_type: "tts"
target:
  entity_id: media_player.echo_dot_kitchen
```

### Troubleshooting

- **Amazon authentication fails:** Ensure your Amazon account has MFA enabled
  via an authenticator app (not SMS). Go to Amazon > Account > Login & Security
  > 2-Step Verification to set it up.

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
modules/nixos/home-assistant/
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

**Trigger for restructuring:** when `default.nix` exceeds ~200 lines or
when you start maintaining more than a handful of automations. Until then,
keeping everything in one file is simpler.

**How to restructure:** split `default.nix` into the files above, update
the `imports` list in `base.nix`, and move `configuration.yaml` into
`config/configuration.yaml`. No Nix semantics change — it is a mechanical split.
