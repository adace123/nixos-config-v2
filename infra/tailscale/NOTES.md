# Tailscale tailnet policy — operator notes

Managed in `infra/tailscale/` (`tailscale_acl.policy`, HuJSON). `tofu plan`
is the diff; `tofu apply` from the laptop only. OAuth creds live OUTSIDE the
repo (`~/.config/tailscale-oauth.env`, chmod 600). Local state (deliberate —
see `providers.tf`).

**Debugging rule: check the policy before blaming the server.** Every denied
flow below fails silently at the filter — the server never sees the packet.

## Tags and ports

| Tag / device | Ports | Notes |
|---|---|---|
| endor + S23 (UNTAGGED, `autogroup:member`) | → servers `tcp:443`; → internet via exit node | Personal devices. Never tag without rewriting member grants. |
| endor (host alias) | → servers `tcp:22` | Root-capable network path for deploys. |
| s23 + other members | → dathomir `tcp:22` | Herdr mobile app drives herdr-core. `nixos` is **accepted** (the app can't carry check mode); `root` still checks. No path to coruscant. |
| `tag:server-ha` (coruscant 100.66.226.84) | → dathomir `tcp:443` (beszel agent out) | Home Assistant via Caddy :443. Exit-node offer (`0.0.0.0/0`) approved in console. |
| `tag:server-infra` (dathomir 100.89.136.120) | → coruscant `tcp:443` (liveness); → self `tcp:443` (hairpin) | Beszel hub + Pocket ID via Caddy :443. |
| `tag:agent-muse` (muse 100.82.236.107) | → servers `tcp:443` only | Meta Muse agent. No :22, no internet. |
| Home LAN `192.168.4.0/22` via coruscant | members → LAN `*` (all ports) | Subnet route advertised by coruscant (`hosts/coruscant/default.nix`); auto-approved for `tag:server-ha`. Servers and muse have no path in. **Known edge:** coruscant's own services at its LAN IP are now member-reachable too — see below. |
| cachyos (UNTAGGED, 100.110.142.85) | members → cachyos `tcp:22`; `dale` via Tailscale SSH (`check`, 12h) | Personal CachyOS box, same owner as endor. Untagged, so the ssh rule rides `autogroup:self` — Tailscale refuses a hostname or IP in an ssh `dst`. `dale` is `wheel`, hence check mode. No server-side path in. |
| `tag:machine` / `tag:nixos-machine` | legacy | Both servers still carry `tag:nixos-machine` (console). Strip in console, then drop from policy (follow-up). |

## Subnet route (home LAN)

coruscant advertises `192.168.4.0/22` (the eero LAN — `end0` is
`192.168.4.53/22`, broadcast `192.168.7.255`; the eero nodes live at
`192.168.6.51`/`.52`, so a `/24` would miss them) as a subnet route, so
personal devices can reach LAN devices that do not run Tailscale — router,
printers, cameras, ESPHome nodes, smart plugs — by their LAN IP, from
anywhere on the tailnet. Three pieces, all in this PR: the Nix flag in
`hosts/coruscant/default.nix` / `modules/nixos/common.nix`, the
`autoApprovers.routes` entry in `tailscale.tf`, and the member grant to the
`/22`. Advertising alone does nothing without the other two.

### coruscant's own LAN IP is a member destination

Granting the whole `/22` also grants coruscant's own LAN IP, so member
devices reach coruscant's node services there and the closures below only
hold on the tailnet IP, not the LAN IP:

- `:8123` — Home Assistant listens on `0.0.0.0` (device discovery needs it,
  see `modules/nixos/home-assistant/default.nix`), so members hit HA raw,
  bypassing the Caddy/Pocket-ID path.
- `:22` — coruscant's sshd is reachable from every member device over the
  LAN IP; the `endor`-only `tcp:22` grant is enforced at the tailnet IP
  only. Auth still gates it (key-only, no shared logins), and the deny
  tests that pin `coruscant:22` test the tailnet IP, not this one.

Accepted for now: the LAN grant is the feature (router admin, printers,
cameras, ESPHome, plugs), coruscant sits inside that /22, and members are
the owner's own devices. Follow-up if this ever matters: bind HA to
`127.0.0.1` (Caddy already proxies it), or narrow the grant below the
router's own address. Note the ACL is enforced on the *sender's* filter
(Tailscale docs: "To restrict access to a subnet, make sure that no ACL
grants access to those routes"), so no coruscant-side change closes this.

Order matters: apply the policy **before** the first switch advertises
the route, then deploy coruscant. autoApprovers only catch the first
advertisement — a route that landed before the policy must be approved in
the console once. This workspace is its own root module with local state,
so the `infra/justfile` `tf` recipe (OCI/Cloudflare) does **not** touch the
policy; apply from `infra/tailscale/`:

```bash
cd infra/tailscale
set -a; . ~/.config/tailscale-oauth.env; set +a   # TS_CLIENT_ID / TS_CLIENT_SECRET
TF_VAR_tailscale_oauth_client_id="$TS_CLIENT_ID" \
TF_VAR_tailscale_oauth_client_secret="$TS_CLIENT_SECRET" \
  tofu plan   # then: tofu apply
```

The `tailscaled-set` oneshot note from the exit-node setup applies here
too: the first switch that adds the flag does not start it on an
already-running daemon — run `sudo systemctl start tailscaled-set` once,
or reboot.

Then verify from a device *off* the LAN (macOS/iOS/Android accept routes
by default; Linux needs `tailscale set --accept-routes`): `tailscale
status` should show the route, and e.g. the LAN gateway should answer.

Live test targets on this LAN (verified from coruscant's neighbour table
and port probes): `192.168.4.1` gateway (ICMP only — eero exposes no web
admin, so an `:80` test there proves nothing), `192.168.4.35:80` Samsung
TV HTTP API, `192.168.4.26` Fire TV (ADB 5555, Cast 8009), `192.168.4.37`
Kasa plug, `192.168.4.53` coruscant itself (HA `:8123` raw), and
`192.168.6.51`/`.52` eero nodes / `192.168.6.73` above the old /24
boundary to prove the widened route. Do not test `192.168.4.20` — that is
endor's own LAN IP, so the packet leaves and returns to the same machine.

## Closed by absence (no grant = denied)

- Raw Pocket ID `:1411` (plaintext + `TRUST_PROXY=true`) — cleanup: bind to 127.0.0.1.
- Hub backend `:8090` (localhost-only).
- Servers → personal devices (any port). Servers → internet.

## SSH (`check` for root, `accept` for nixos)

Needs BOTH the `:22` grant and the `ssh` rule. `root` is `check` (12h) on every
server tag; `nixos` is `accept` for members, because the Herdr mobile app's SSH
client cannot carry the interactive check — dathomir's log showed the connection
handled and then no session. Expired check window: BatchMode root deploys FAIL —
re-auth via any interactive `ssh` (prints the sign-in URL), re-run. The phone's
`:22` path is limited to dathomir, for the Herdr mobile app.

`nixos` is `wheel` with passwordless sudo on dathomir, so the `accept` path is
root-equivalent there; the stricter alternative is tagging the phone and
accepting only `tag:mobile`.

`cachyos` is the same story in the other direction: `dale` is `wheel` (verified
on the box), so members reach it only through a `check` rule. Its `dst` is
`autogroup:self`, not the host alias — the ssh block only accepts tags,
`autogroup:self`, or a same-user selector, so `"dst": ["cachyos"]` is rejected
by `/acl/validate` with `invalid dst`. The network half still names the alias
(`{"src": ["autogroup:member"], "dst": ["cachyos"], "ip": ["tcp:22"]}`); both
halves are required. `sshTests` *do* take host aliases, so
`{"src": "endor", "dst": ["cachyos"], "check": ["dale"]}` pins the result.

## If a host re-registers with a new IP

Update `hosts` in `tailscale.tf` immediately — grants AND tests resolve the
same aliases, so the policy tests cannot catch a stale IP. Run
`scripts/tailscale-inventory-check.sh` alongside every apply; it diffs
`hosts` against the live device inventory.
