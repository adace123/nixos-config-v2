# Apply #2 (final). Validated against POST /acl/validate. Tagging verified; transitional grant removed.
#
# First run against the live tailnet:
#   tofu import tailscale_acl.policy acl
#
# Reset is deliberately NOT enabled: destroying this workspace must leave the
# tailnet policy alone, never wipe it.
resource "tailscale_acl" "policy" {
  acl = <<EOF
{
	// Apply #2 (final): tagging verified (muse -> dathomir -> coruscant), so
	// the transitional member->member grant, autogroup:self, and the pre-new
	// tags go. Servers can no longer reach personal devices at all.
	//
	// Conventions (unchanged from apply #1):
	// - Personal devices (endor Mac, Aaron's S23) stay UNTAGGED.
	// - Host aliases as grant/test sources match by source IP (live-validated).
	//   If a host re-registers with a new tailnet IP, update hosts promptly —
	//   the policy tests CANNOT catch this. Step-6 hardening: inventory check
	//   (hosts vs GET /devices) run alongside applies.
	// - Port 22 needs BOTH a network grant and an ssh rule. The endor-only
	//   tcp:22 grant is the per-device lever; only the Mac holds root-capable
	//   network paths. Deploys ride this grant either way.
	// - Pocket ID via Caddy :443 only; raw :1411 and hub :8090 have NO grant —
	//   absence is the closure. Cleanup: bind Pocket ID to 127.0.0.1.
	// - Exit-node grant names ANY approved exit node, and the autoApprovers
	//   below approve every server we tag that way *when it advertises* (a node
	//   already advertising before the policy changed must re-advertise once).
	//   Two offers are intended: coruscant (home egress, dies with the home
	//   uplink) and dathomir (OCI egress, independent of it). "Approved" is not
	//   the same as "advertising" — `tailscale exit-node list` hides both
	//   mismatches and is the only real check.
	"hosts": {
		"endor": "100.69.133.88",
		"s23": "100.110.89.98",
		"coruscant": "100.66.226.84",
		"dathomir": "100.89.136.120",
		"muse": "100.82.236.107",
	},
	"tagOwners": {
		// tag:machine / tag:nixos-machine: KEPT because both servers still
		// carry tag:nixos-machine (console-added). Drop these entries only
		// after removing that tag from both devices in the console.
		"tag:ci": ["autogroup:admin"],
		"tag:machine": ["autogroup:admin"],
		"tag:nixos-machine": ["autogroup:admin"],
		"tag:server-ha": ["autogroup:admin"],
		"tag:server-infra": ["autogroup:admin"],
		"tag:agent-muse": ["autogroup:admin"],
	},
	// Exit-node approval is otherwise a console click per device, and it is
	// silently absent after a VPS is replaced (a fresh registration is a new
	// device). Auto-approving the server tags keeps `tailscale up
	// --advertise-exit-node` sufficient on its own; the tags are owner-only, and
	// the internet grant below is member-scoped, so a server can only *be* an
	// exit node — it still has no way to *use* one. (A policy `test` cannot pin
	// this: test accept/deny entries parse as `host:port`, so
	// `autogroup:internet` there is rejected as an unknown host.)
	"autoApprovers": {
		"exitNode": ["tag:server-ha", "tag:server-infra"],
	},
	"grants": [
		// Personal devices -> servers: HTTPS UI + Pocket ID auth (via Caddy).
		{"src": ["autogroup:member"], "dst": ["coruscant", "dathomir"], "ip": ["tcp:443"]},
		// Endor-only :22 network path (Tailscale SSH + plain-OpenSSH deploys).
		{"src": ["endor"], "dst": ["coruscant", "dathomir"], "ip": ["tcp:22"]},
		// Herdr's mobile app drives herdr-core over SSH, so a personal device
		// needs a real :22 path to dathomir. Scoped to dathomir on purpose:
		// coruscant keeps its endor+CI-only path, and the `check` ssh rule below
		// still gates every connection on a fresh IdP sign-in.
		{"src": ["autogroup:member"], "dst": ["dathomir"], "ip": ["tcp:22"]},
		// CI deploy runner (tag:ci, ephemeral GitHub Action node): :22 to both
		// servers. Dsts are the host aliases (same as tests resolve). Keep the
		// human check-mode rule below untouched — this is the only accept path.
		{"src": ["tag:ci"], "dst": ["coruscant", "dathomir"], "ip": ["tcp:22"]},
		// Personal devices -> internet via exit node (Option A). Servers are
		// tagged, so this now truly covers only personal devices.
		{"src": ["autogroup:member"], "dst": ["autogroup:internet"], "ip": ["*"]},
		// coruscant -> dathomir:443: beszel agent dials OUT to the hub.
		{"src": ["coruscant"], "dst": ["dathomir"], "ip": ["tcp:443"]},
		// dathomir -> coruscant:443: liveness check (tailscale ping needs no
		// grant; TCP/443 proves HA alive).
		{"src": ["dathomir"], "dst": ["coruscant"], "ip": ["tcp:443"]},
		// dathomir self-hairpin: agent + hub OIDC discovery via tailnet name.
		// Probably unnecessary; kept as harmless, removal trial later.
		{"src": ["dathomir"], "dst": ["dathomir"], "ip": ["tcp:443"]},
		// muse (tag:agent-muse): outbound 443 to both servers only.
		{"src": ["muse"], "dst": ["coruscant", "dathomir"], "ip": ["tcp:443"]},
		// Member debugging: ping between member devices.
		{"src": ["autogroup:member"], "dst": ["autogroup:member"], "ip": ["icmp:*"]},
		{"src": ["autogroup:member"], "dst": ["coruscant", "dathomir"], "ip": ["icmp:*"]},
	],
	"ssh": [
		// Herdr's mobile app drives herdr-core over Tailscale SSH, but its SSH
		// client cannot carry the interactive check: the connection opens and
		// stalls on the auth welcome (dathomir's log shows "handling conn" and no
		// session). So a member's nixos login to dathomir is accepted, not
		// checked. Scoped to dathomir + nixos: root still has to pass the check
		// below. Caveat: nixos is wheel with passwordless sudo on dathomir, so
		// this path is root-equivalent — it is the price of the app working.
		{
			"action": "accept",
			"src": ["autogroup:member"],
			"dst": ["tag:server-infra"],
			"users": ["nixos"],
		},
		// check mode (12h): identity PLUS fresh IdP sign-in, for root only.
		// Only SSH mitigation until Tailscale patches Tailworm. BatchMode
		// deploys FAIL past expiry — re-auth in browser, re-run. autogroup:self
		// REMOVED: both servers are tagged. `nixos` is deliberately NOT here:
		// it is accepted above so the Herdr mobile app can connect at all, and
		// on dathomir nixos is wheel with passwordless sudo anyway.
		{
			"action": "check",
			"checkPeriod": "12h",
			"src": ["autogroup:member"],
			"dst": ["tag:machine", "tag:nixos-machine", "tag:server-ha", "tag:server-infra"],
			"users": ["root"],
		},
		// CI deploy runner: accept, never check — a tagged source cannot do
		// check mode, and there is no browser headless. Root only, Tailscale
		// SSH, no key. Human check-mode rule above untouched.
		{
			"action": "accept",
			"src": ["tag:ci"],
			"dst": ["tag:server-ha", "tag:server-infra"],
			"users": ["root"],
		},
	],
	"tests": [
		{"src": "endor", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443", "coruscant:22", "dathomir:22"]},
		{"src": "s23", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443", "dathomir:22"]},
		{"src": "coruscant", "proto": "tcp", "accept": ["dathomir:443"]},
		{"src": "dathomir", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443"]},
		{"src": "muse", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443"]},
		{"src": "tag:ci", "proto": "tcp", "accept": ["coruscant:22", "dathomir:22"]},
		{"src": "endor", "proto": "icmp", "accept": ["coruscant:0", "dathomir:0"]},
		// Full isolation (transitional grant gone): servers cannot initiate to
		// personal devices; raw :1411/:8090 closed to everyone; muse has no :22
		// path and s23 has none to coruscant.
		{"src": "endor", "deny": ["dathomir:1411", "dathomir:8090"]},
		{"src": "s23", "deny": ["dathomir:1411", "dathomir:8090", "coruscant:22"]},
		{"src": "coruscant", "deny": ["endor:443", "s23:443", "dathomir:1411", "dathomir:8090"]},
		{"src": "dathomir", "deny": ["endor:443", "s23:443", "dathomir:1411", "dathomir:8090"]},
		{"src": "muse", "deny": ["dathomir:1411", "dathomir:8090", "coruscant:22", "dathomir:22"]},
	],
	"sshTests": [
		{"src": "endor", "dst": ["coruscant", "dathomir"], "check": ["root"]},
		{"src": "tag:ci", "dst": ["coruscant", "dathomir"], "accept": ["root"]},
	],
}

EOF
}
