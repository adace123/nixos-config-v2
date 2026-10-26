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
| endor only (host alias) | → servers `tcp:22` | Only root-capable network path. Phone has none. |
| `tag:server-ha` (coruscant 100.66.226.84) | → dathomir `tcp:443` (beszel agent out) | Home Assistant via Caddy :443. Exit-node offer (`0.0.0.0/0`) approved in console. |
| `tag:server-infra` (dathomir 100.89.136.120) | → coruscant `tcp:443` (liveness); → self `tcp:443` (hairpin) | Beszel hub + Pocket ID via Caddy :443. |
| `tag:agent-muse` (muse 100.82.236.107) | → servers `tcp:443` only | Meta Muse agent. No :22, no internet. |
| `tag:machine` / `tag:nixos-machine` | legacy | Both servers still carry `tag:nixos-machine` (console). Strip in console, then drop from policy (follow-up). |

## Closed by absence (no grant = denied)

- Raw Pocket ID `:1411` (plaintext + `TRUST_PROXY=true`) — cleanup: bind to 127.0.0.1.
- Hub backend `:8090` (localhost-only).
- Servers → personal devices (any port). Servers → internet.

## SSH (`check`, 12h)

Needs BOTH the `:22` grant and the `ssh` rule. `users: root + nixos`
exactly (`nonroot` would admit any Unix account on tagged dsts). Expired
window: BatchMode deploys FAIL — re-auth via any interactive `ssh` (prints
the sign-in URL), re-run. Phone has no `:22` network path at all.

## If a host re-registers with a new IP

Update `hosts` in `tailscale.tf` immediately — grants AND tests resolve the
same aliases, so the policy tests cannot catch a stale IP. Run
`scripts/tailscale-inventory-check.sh` alongside every apply; it diffs
`hosts` against the live device inventory.
