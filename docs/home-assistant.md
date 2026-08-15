# Home Assistant

This document describes the current Home Assistant setup on `coruscant` and the
intended future structure.

## Current Layout

Home Assistant runs as a rootless Podman container managed by NixOS. The relevant
files are:

```text
modules/nixos/home-assistant/
├── automations/          # Declarative, version-controlled automations
├── custom_components/    # Git-tracked custom components (copied on activation)
│   └── google_health_workouts/  # Per-workout sensors from the Google Health API
├── default.nix           # Container, MQTT, Zigbee2MQTT, ESPHome, user setup
└── configuration.yaml    # HA base config template (secrets injected by SOPS)
```

`default.nix` covers:

- **Podman container** (`ghcr.io/home-assistant/home-assistant:latest`)  
  Auto-starts, mounts `/var/lib/hass`, uses host networking for device discovery.
- **Firewall** — opens TCP 8123 plus UDP 9999 and the ephemeral range
  (32768–60999) for TP-Link Kasa/Tapo broadcast discovery; modern python-kasa
  binds a random source port and devices reply there, which conntrack does not
  treat as ESTABLISHED.
- **SOPS template rendering** — injects `time.timeZone` and
  `home-assistant-external-domain` into `configuration.yaml` before HA starts.
- **Mosquitto** MQTT broker (port 1883, localhost only).
- **Zigbee2MQTT** (port 8091, Sonoff Zigbee dongle via stable
  `/dev/serial/by-id/...` path).
- **ESPHome** (port 6052).
- **Podman auto-update** — pulls newer images weekly.
- **`hass` system user** with `dialout`, `gpio`, `i2c` group membership.

Automations use a hybrid model. Files under `automations/` are declarative and
copied into the persistent Home Assistant config directory during NixOS activation.
Automations created in the Home Assistant UI are stored in the persistent, writable
`/var/lib/hass/automations.yaml`; activation initializes that file only when it does
not exist, so later deployments preserve UI changes.

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

## Alexa Notify Me (REST skill)

For one-way announcements without an Amazon login in Home Assistant, the
**Notify Me** Alexa skill
([notifymyecho.com](https://www.notifymyecho.com/)) works via a simple REST
API: HA calls `api.notifymyecho.com` and every Echo linked to the skill
announces the message.

### Setting up Notify Me

1. Enable the Notify Me skill in the Alexa app and launch it once
   ("Alexa, open Notify Me") to get the access code.
2. Add the access code to the SOPS secrets file as
   `alexa-notify-me-api-key` (see [docs/secrets.md](secrets.md)).
3. The key is injected into `configuration.yaml` via the SOPS template
   placeholder `__ALEXA_NOTIFY_ME_API_KEY__`, which populates the
   `rest_command.alexa_notify` integration.

### Sending an announcement

```yaml
service: rest_command.alexa_notify
data:
  message: "The laundry is done"
```

The `message` is URL-encoded automatically (`{{ message | urlencode }}`).
Announcements reach **all** Echo devices linked to the skill; use the Alexa
Devices integration above when you need per-device targeting via
`media_player`.

Example: the Hyundai alerts automation (`automations/hyundai-alerts.yaml`)
announces low fuel, brake fluid, washer fluid, low 12V battery, key fob
battery, tire pressure, and telematics-staleness warnings through this
command whenever the corresponding sensor indicates a problem.

## Google Health Workouts (custom component)

A small git-tracked custom integration (`google_health_workouts`) that exposes
per-workout sensors from the [Google Health API](https://developers.google.com/health)
`exercise` data type. The stock `google_health` integration only exposes daily
rollups; this one fills the per-workout gap (distance, average speed, average
heart rate, calories, elevation).

Health data now flows through two canonical integrations:

- **`google_health`** (official, built-in) — daily rollups: steps, distance,
  active/total calories, floors, weight, resting heart rate, body fat, sleep
  durations, hydration, and Charge 6 / MobileTrack battery + last-sync.
- **`google_health_workouts`** (this repo) — per-workout session details.

The third-party **Health Sync by ResiyHome** integration (HACS) was removed as
redundant (2026-08-12); its workout type/duration and daily aggregates are
covered by the two integrations above. Its component files remain in
`custom_components/` (inactive without a config entry) and can be uninstalled
from HACS if desired. Its exercise/active-zone-minute sensors were dropped from
the dashboard (no `google_health` equivalent).

Sensors created per workout: type, duration, distance (mi), average speed
(mph), average heart rate (bpm), calories (kcal), elevation (ft), plus a
30-day session count. The type sensor carries session attributes (display
name, start/end time, active duration, GPS flag), and
`sensor.workouts_last_30_days` carries a `workouts` attribute — a newest-first
list of recent sessions (type, date, distance, duration, heart rate, speed,
calories) that the dashboard's Workout Log card renders.

- Reuses the **same Google Cloud OAuth client** as the stock `google_health`
  integration (add it under the `google_health_workouts` domain in
  Settings → Devices & Services → Application Credentials, or the box may
  already have it pre-registered).
- Requires the `activity_and_fitness.readonly` OAuth scope.
- Polls every 10 minutes; sensors are `sensor.last_workout_*` and
  `sensor.workouts_last_30_days`.
- Tracked in `custom_components/google_health_workouts/` and copied into
  `/var/lib/hass/custom_components/` during NixOS activation (same mechanism
  as the pinned HACS install).

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
