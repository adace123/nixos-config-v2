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
├── ring-mqtt.nix         # Ring → MQTT bridge + doorbell RTSP (coruscant only)
└── configuration.yaml    # HA base config template (secrets injected by SOPS)
```

  Auto-starts, mounts `/var/lib/hass`, uses host networking for device discovery.

- **Firewall** — opens TCP 8123 plus UDP 9999 and the ephemeral range
  (32768–60999) for TP-Link Kasa/Tapo broadcast discovery; modern python-kasa
  binds a random source port and devices reply there, which conntrack does not
  treat as ESTABLISHED.
- **ring-mqtt** (`ring-mqtt.nix`, coruscant only) — Ring → MQTT bridge
  (podman, `docker.io/tsightler/ring-mqtt:5.9.3`) plus authed doorbell RTSP at
  `127.0.0.1:8554/<ring-id>_live`, consumed by HA's embedded go2rtc for
  low-latency WebRTC dashboards. First boot needs the one-time auth UI on
  `127.0.0.1:55123` (SSH forward) to store the Ring refresh token.
- **Podman auto-update** — pulls newer images weekly.
- **`hass` system user** with `dialout`, `gpio`, `i2c` group membership.

Automations use a hybrid model. Files under `automations/` are declarative and
copied into the persistent Home Assistant config directory during NixOS activation.
Automations created in the Home Assistant UI are stored in the persistent, writable
`/var/lib/hass/automations.yaml`; activation initializes that file only when it does
not exist, so later deployments preserve UI changes.

The **Home Assistant issue alert** automation (phone push on ERROR/CRITICAL log
events) is declarative (`automations/home-assistant-issue-alert.yaml`). It filters
out transient, self-recovering errors — TP-Link Kasa device timeouts and the
Firebase push client's recurring "Incorrect padding" error — and throttles
ERROR-level alerts to one per hour (CRITICAL always passes).

Caddy provides HTTPS reverse-proxy access to HA on port 443 using Cloudflare
DNS-01 ACME (see `caddy.nix`).

## Secrets Required

| SOPS secret key | Used by |
|-----------------|---------|
| `home-assistant-external-domain` | `configuration.yaml` template, Caddy virtual host |
| `cloudflare-api-key` | Caddy DNS-01 challenge |
| `oidc-client-id` | Pocket ID OIDC client for `auth_oidc` in `configuration.yaml` |
| `oidc-discovery-url` | Pocket ID well-known endpoint for `auth_oidc` in `configuration.yaml` |
| `alexa-notify-me-api-key` | `rest_command.alexa_notify` in `configuration.yaml` |
| `ring-livestream-pass` | ring-mqtt RTSP auth (`ring` user); rotate with `sops set`, unit bounces via `restartUnits` |

See [docs/secrets.md](secrets.md) for how to add or rotate secrets.

## Ring doorbell (ring-mqtt)

The official `ring` integration stays until ring-mqtt covers the same ground —
running both against one account risks API throttling, so deleting the `ring`
config entry is the endgame once ding/motion/live-view all flow through MQTT +
RTSP.

`ring-mqtt.nix` (imported by `default.nix`, gated to coruscant because
`base.nix` is shared with threepio) runs `docker.io/tsightler/ring-mqtt:5.9.3`
as a podman container beside HA (docker.io, not ghcr.io — ghcr denies
anonymous token issuance for this repo from every network tried):

- MQTT to `127.0.0.1:1883` (same `::1` trap zigbee2mqtt hit — `localhost`
  resolves IPv6-only here). Entities arrive via MQTT discovery, no HA config.
- Doorbell RTSP at `127.0.0.1:8554/343ea4133f75_live` (Ring ID from the
  device registry). HA's embedded go2rtc WebRTC-proxies any RTSP source, so
  no standalone go2rtc module exists — add a generic-camera entity named
  e.g. "Ring Doorbell Stream" with this stream source (leave still-image
  blank; the wizard rejects its template form and the snapshot entity only
  gains state after first publish).
- RTSP auth is on (`ring` user, password in `ring-livestream-pass`): the
  container is `--network=host` like HA (bridge loopback is the container
  itself, which is how MQTT `ECONNREFUSED`ed at first), so the port is on
  all interfaces and auth is what protects tailnet clients. The password
  is hex-only so it pastes into URLs unescaped; stream source is
  `rtsp://ring:<pass>@127.0.0.1:8554/343ea4133f75_live`.
- First boot: no token exists, so the container serves its auth UI on
  `127.0.0.1:55123`. Forward it (`ssh -L 55123:127.0.0.1:55123
  root@coruscant.local`), sign in with Ring credentials + 2FA, and the UI
  stops itself. The token lands in `/var/lib/ring-mqtt/ring-state.json`,
  which the restic job backs up under `--tag ring-mqtt` (the only
  non-reproducible state; `config.json` re-renders from the module).
- `enable_modes`/`enable_panic` stay off; H.264 default (doorbell is 1080p,
  HEVC buys nothing and trips the known FFmpeg/go2rtc freeze).
- Streams are on-demand only: a battery doorbell sleeps between events, and
  Ring suppresses motion/ding alerts while streaming. No continuous/NVR use.

## Pocket ID Login (passkeys via OIDC)

Sign-in is delegated to [Pocket ID](https://pocket-id.org) on dathomir (see
[docs/dathomir.md](dathomir.md)) through the
[hass-oidc-auth](https://github.com/christiaangoossens/hass-oidc-auth)
custom component (`auth_oidc`), packaged declaratively in `default.nix`
(`fetchzip` v1.2.1, copied to `custom_components/auth_oidc` at activation
alongside HACS). HA is a **public client** (PKCE, no secret — the upstream
recommendation for home use); `client_id` and `discovery_url` render from
the `oidc-client-id` / `oidc-discovery-url` SOPS secrets via the
`hass-configuration.yaml` template, and `http.trusted_proxies` trusts only
Caddy on 127.0.0.1 so the OIDC callback URL builds correctly.

`display_name` is "Pocket ID" and `features.default_redirect` skips the
welcome screen straight to Pocket ID; the local username/password login
stays available at `https://<home-assistant-external-domain>/?skip_oidc_redirect=true`
(that parameter is the integration's own escape hatch, rendered on its
welcome page — not an invention).

### Setup (one-time, in Pocket ID)

1. Open `https://id.<domain>` → **OIDC Clients → Add OIDC Client**.
2. Name: `Home Assistant`. Callback URL:
   `https://<home-assistant-external-domain>/auth/oidc/callback`.
3. Tick **Public Client** (PKCE is marked automatically). Save.
4. Copy the **Client ID** and **OIDC Discovery URL**, then store them:

   ```bash
   just edit-secrets secrets/coruscant.yaml   # and threepio.yaml
   ```

   Set `oidc-client-id` to the real client ID (replacing the
   `PENDING-create-oidc-client-in-pocket-id` placeholder) and confirm
   `oidc-discovery-url` matches. Redeploy.

`features.automatic_user_linking` links the OIDC identity to the existing
HA user on first login (instead of minting a second, non-admin profile),
and `require_existing_user` means unknown OIDC identities can never create
accounts. The link matches on the OIDC **username** claim, so the Pocket ID
username must exactly equal the HA username — check with local login first
if a first login is denied. Only one HA user exists here, so no group→role
mapping (`roles.admin`/`roles.user`) is configured.

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

## Recorder and history retention

`recorder:` in `configuration.yaml` keeps **30 days** (`purge_keep_days: 30`) in
SQLite at `/var/lib/hass/home-assistant_v2.db`, with `auto_purge` and
`auto_repack` both on.

- 60 days took the database to 960M in October 2026, which was most of the 1.1G
  config directory and the bulk of every nightly restic backup. 30 days roughly
  halves steady-state size; nothing in the dashboards reads further back.
- `auto_repack` matters as much as the purge: a purge deletes rows but the SQLite
  file keeps its size until a repack rewrites it. A repack needs free space
  roughly equal to the database, and it pauses recorder writes while it runs, so
  expect a short gap around it on the Pi.
- `car_scripts/car_rate.py` reads this database directly and averages over
  `WINDOW_DAYS`. That constant must stay at or below `purge_keep_days`, because a
  window longer than retention silently averages a shorter span instead of
  failing.

To reclaim space by hand after a big purge: `podman exec home-assistant
sqlite3 /config/home-assistant_v2.db VACUUM` (or let `auto_repack` do it).

## Monitoring Logs

```bash
just hass-logs                              # last 50 lines
just hass-logs LINES=200                    # last 200 lines
just hass-logs FILTER="error|recorder"      # filtered
```

The `logger:` block in `configuration.yaml` pins noisy loggers: `homeassistant`
at `info`, `homeassistant.components` at `warning`, and `aioamazondevices` at
`warning` — the Alexa devices library logs under its own name, so the
`components` filter never matched it, and its per-device retry chatter was the
largest single contributor to `coruscant`'s journal. Drop it to `error` if the
cached-value warnings are still too loud.

## Backups

Home Assistant's persistent data (`/var/lib/hass`) is backed up nightly to
Cloudflare R2 with Restic and checked weekly. See
**[docs/backups.md](backups.md)** for schedule, retention, listing, and the
restore procedure.

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
├── ring-mqtt.nix         # Ring → MQTT bridge + doorbell RTSP
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
