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

- **Firewall** — opens TCP 8123, UDP 9999 and 38899/38900, plus the ephemeral
  range (32768–60999). 9999 + ephemeral is for TP-Link Kasa/Tapo discovery:
  modern python-kasa binds a random source port and devices reply there, which
  conntrack does not treat as ESTABLISHED. 38899/38900 are WiZ (pywizlight binds
  both fixed ports — see [WiZ lights](#wiz-lights)).
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

The official `ring` integration is gone — deleted once ding/motion/live-view
were all confirmed through MQTT + RTSP (single client, no throttling risk).
Re-adding it later needs a fresh Ring 2FA sign-in.

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

### Never put a live camera on a dashboard

A `picture-entity` card with `camera_view: auto` falls back to the **live
stream** when the camera has no still-image URL — and this camera has none.
Every dashboard view then woke the doorbell for a ~20s Ring signaling session,
roughly once per refresh (observed 2026-10-27: 14 sessions in 20 minutes).
Two costs, one of them silent:

- battery drain on a device that sleeps between events;
- **Ring suppresses motion and ding alerts while a stream is active**, so real
  events were being missed for as long as the dashboard stayed open — the
  likely reason a walk-past produced no clip.

The dashboard card therefore points at `camera.front_door_snapshot` (a still
image refreshed on motion, no stream). If a card must show live video, set
`camera_view: live` deliberately and close the tab afterwards. The generic
RTSP camera is for `camera.record` and on-demand viewing, not ambient display.

### Recordings and playback

`automations/front-door-record.yaml` records a 30s clip on ding or motion
(`camera.record` with explicit `duration`; HA defaults it to 30s anyway) into
`/media/doorbell/<YYYY-MM-DD_HH-MM-SS>.mp4`, then pushes a phone notification
whose `clickAction` deep-links to that clip. `front-door-purge.yaml` deletes
clips older than 7 days at 03:15. Clips are **not** backed up to R2.

Clips appear under Media → Local Media → doorbell. That browser is
**read-only** — there is no delete action, so removing a clip means
`rm /media/doorbell/<file>` on the host (or waiting for the purge). Playback
works in the companion app but can stall on the first frame in desktop
browsers (seen in Dia); the files are sound (faststart mp4, `moov` before
`mdat`), so it is the browser's decoder and not the recording. Use the app or
Safari for clips.

A walk-past already out of frame before the Ring cloud push lands is not
recoverable: the latency is device wake plus cloud round-trip, not the
automation. There is no pre-buffer — Ring only sends events, and streaming
continuously to create one would suppress the very alerts being recorded.
Detection tuning (motion zones, sensitivity, advanced motion) moves that
window earlier; nothing in HA can. A local PIR aimed at the walkway, firing
`camera.record` over Zigbee, is the only genuinely faster trigger.

## WiZ lights

WiZ bulbs (Philips Smart LED with WiZ Connected, plus the ~20 white-label
brands) use Home Assistant's built-in `wiz` integration — pywizlight is already
in the official `ghcr.io/home-assistant/home-assistant` image, so there is no
`custom_components` entry and nothing to package. Control is local UDP; the
cloud is only needed by the WiZ app for setup.

Three things have to be true before HA sees the bulb:

1. **The bulb is on the same L2 network as coruscant.** Discovery is a UDP
   broadcast to `255.255.255.255:38899`; routed subnets, the eero guest network
   (client isolation) and the bulb's own pairing-mode AP all fail it. The bulb
   is 2.4 GHz only, so join it to the main SSID in the WiZ app.
2. **Local communication is enabled** — WiZ app → settings (top left) →
   security → **Allow local communication**. On by default, but a cloud-only
   bulb answers nothing locally.
3. **UDP 38899 and 38900 are open inbound** (`default.nix`). pywizlight binds
   38899 for the discovery socket and 38900 for push updates, and the bulb
   unicasts back to those fixed ports — with `--network=host` that is host
   input, not a conntrack-matched reply, so the nixos firewall drops it.
   Discovery then silently finds nothing and push state never arrives.

4. **"Verified control" must be off on firmware 1.3x (ESP25 modules).** Reads
   answer unsigned, but `setPilot` comes back `-32602 Invalid params` unless the
   request carries a base64 HMAC-SHA256 signature. HA 2026.11 pins
   `pywizlight==0.6.3`, which cannot sign (signing landed in 0.6.7, and HA has no
   config for the key), so the integration reads state and fails every write
   with `WizLightConnectionError: Error recieved: {'code': -32602, …}`. The
   app-side escape hatch: WiZ app → **Settings → Security → Allow all
   controls** (sbidy/pywizlight#213, confirmed on ESP25 1.34/1.38). Leave **Allow
   local communication** on. With it on, unsigned writes work and no
   custom component is needed; the alternative — the home's `udp_signing_key`
   from the WiZ app's home export, 32 hex chars, passed as `signing_key` — needs
   a pywizlight bump plus HA plumbing that does not exist yet.

Add it in HA with **Settings > Devices & Services > Add Integration > WiZ**
(auto-discovery usually offers it first). If discovery still misses, add the
bulb **by IP** — and pin that IP as a DHCP reservation in the eero app, because
a redialled lease breaks the entry.

Note the bulb MACs seen here (`98:77:D5:*`) are not in HA's DHCP matcher list
(`A8BB50*`, `D8A011*`, `444F8E*`, `6C2990*`, hostname `wiz_*`), so there is no
DHCP-triggered discovery; the integration's own UDP broadcast scan runs at
startup and every 15 min, which is what the 38899 rule above is for.

Also note the entity id: the Kasa "Front door light" entry is disabled but its
entity stays in the registry, so the WiZ device (also called *Front Door Light*)
landed as `light.front_door_front_door_light`. Rename it in the UI if the
doubled name bothers, then update the automation below.

### Porch light on motion

`automations/front-door-light-motion.yaml` fires on the Ring doorbell's **local
MQTT** motion sensor (`binary_sensor.front_door_motion`, via ring-mqtt — not the
Ring cloud event), turns the WiZ bulb on at 100 % / 2700 K, and turns it off 30 s
later. `mode: restart` means each new motion event extends the window instead of
stacking timers.

The gate is `condition: sun.is_set` (sunset → sunrise). Do **not** replace it
with the older `condition: sun` + `after: sunset` alone: that compares against
*today's* sunset and silently stops passing at midnight, which is how the porch
light went dark for the second half of every night.

Probe from any host on the same LAN to separate network problems from HA
problems (coruscant has no `python3` in PATH — run it from the Mac):

```bash
python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(1.2)
s.sendto(b'{"method":"getPilot","params":{}}', ("<bulb-ip>", 38899))
print(s.recvfrom(2048)[0].decode())
PY
```

A WiZ bulb answers with a `{"result":{...}}` getPilot payload. A timeout means
nothing is listening on 38899 at that IP: the bulb is not on this network, the
IP is stale, or local communication is disabled in the app. `nc -u -w1 <ip>
38899` works too, but UDP netcat cannot tell "no device" from "device ignored
us", so prefer the snippet.

## Pocket ID Login (passkeys via OIDC)

Sign-in is delegated to [Pocket ID](https://pocket-id.org) on dathomir (see
[docs/dathomir.md](dathomir.md)) through the
[hass-oidc-auth](https://github.com/christiaangoossens/hass-oidc-auth)
custom component (`auth_oidc`), packaged declaratively in `default.nix`
(`fetchzip` v1.2.1, copied to `custom_components/auth_oidc` at activation
alongside HACS). HA is a **public client** (PKCE, no secret — the upstream
recommendation for home use); `client_id` and `discovery_url` render from
the `oidc-client-id` / `oidc-discovery-url` SOPS secrets via the
`hass-configuration.yaml` template, and reverse-proxy trust (Caddy on
127.0.0.1) lives in the UI now (Settings > System > Network), not YAML —
see below.

`display_name` is "Pocket ID" and `features.default_redirect` skips the
welcome screen straight to Pocket ID; the local username/password login
stays available at `https://<home-assistant-external-domain>/?skip_oidc_redirect=true`
(that parameter is the integration's own escape hatch, rendered on its
welcome page — not an invention).

### Setup (one-time, in Pocket ID)

1. Open `https://id.<domain>` → **OIDC Clients → Add OIDC Client**.
2. Name: `Home Assistant`. Callback URL:
   `https://<home-assistant-external-domain>/auth/oidc/callback`.
3. Tick **Public Client** (PKCE is marked automatically).
4. On the client's **Access** tab, choose **All Users** (or tick the group
   your user belongs to). A UI-created client defaults to **Selected user
   groups** with nothing ticked, which rejects every sign-in with "You are
   not allowed to access this service". Save.
5. Copy the **Client ID** and **OIDC Discovery URL**, then store them:

   ```bash
   just edit-secrets secrets/coruscant.yaml   # and threepio.yaml
   ```

   Set `oidc-client-id` to the real client ID (replacing the
   `PENDING-create-oidc-client-in-pocket-id` placeholder) and confirm
   `oidc-discovery-url` matches. Redeploy.

`features.automatic_user_linking` links the OIDC identity to the existing
HA user on first login (instead of minting a second, non-admin profile).
The link matches on the OIDC **username** claim, so the Pocket ID username
must exactly equal the HA username — otherwise a duplicate is minted
(delete it via local login). Only one HA user exists here, so no
group→role mapping (`roles.admin`/`roles.user`) is configured. Note:
`require_existing_user` (upstream docs) does not exist in the packaged
v1.2.1 — it rejects the config — so it is deliberately absent.

### HTTP settings live in the UI, not YAML

HA 2026.8 migrated the `http:` block (port, `use_x_forwarded_for`,
`trusted_proxies`) into **Settings > System > Network** (stored in
`.storage/http`, covered by the R2 backup like the rest of
`/var/lib/hass`). The YAML block was removed — keeping it trips a Repairs
warning now and breaks in 2027.2. The imported values carry the Caddy trust
(`use_x_forwarded_for`, `127.0.0.1/32` in trusted proxies), so the OIDC
callback still builds its `https://` external URL. If the Network page ever
loses the proxy settings, OIDC login breaks the same way — check there first.

## NextLock smart lock

The NextLock app + gateway is TTLock-compatible. Two integrations are
packaged declaratively in `default.nix` (each `fetchzip` copied to
`custom_components/` at activation alongside HACS) — try the local one
first, keep the cloud one as fallback:

- **TTLock BLE** ([ha-ttlock-ble](https://github.com/roquerodrigo/ha-ttlock-ble),
  `ttlock_ble` v3.12.0): lock/unlock over the Pi's own Bluetooth, no
  gateway or cloud round-trip per operation. A one-time NextLock-app login
  fetches the keys at setup; after that everything stays local. Needs the
  lock in BLE range of coruscant — if the front door is too far, an
  ESPHome Bluetooth proxy near the door is the fix (ESPHome itself is
  currently disabled, see above).
- **TTLock cloud** ([hass-ttlock](https://github.com/jbergler/hass-ttlock),
  `ttlock` v0.17.1): lock/unlock via the gateway through TTLock's cloud,
  with webhook real-time updates. Needs a developer application at
  <https://open.ttlock.com/manager> (approval takes a few days) and Remote
  Unlock enabled in the NextLock app while in Bluetooth range.

### Setup (one-time)

BLE first: Settings > Devices & Services > Add Integration > **TTLock
BLE** — pick the discovered lock (or add manually), sign in once with the
NextLock-app account when prompted (verification code by email if TTLock
hasn't seen this HA before). Cloud fallback: add **TTLock** with the
application Client ID / Secret first, then the NextLock-app username /
password; paste the webhook URL from the Repairs notice into the
application's callback URL at `open.ttlock.com`, then lock/unlock once to
resolve it.

Both provide `lock` / `unlock` plus battery, last-operator and door-state
sensors. Nothing else is wired yet — doorbell-press alerts stay a later
step if the lock turns out to emit them. After deploying, restart the HA
container once (`systemctl restart podman-home-assistant`) so the new
components load — activation only copies them into place.

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
