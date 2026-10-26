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
	// - Exit-node grant names ANY exit node; "coruscant is the only one" is an
	//   operational invariant. Servers are tagged now, so it truly covers only
	//   personal devices.
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
		"tag:machine": ["autogroup:admin"],
		"tag:nixos-machine": ["autogroup:admin"],
		"tag:server-ha": ["autogroup:admin"],
		"tag:server-infra": ["autogroup:admin"],
		"tag:agent-muse": ["autogroup:admin"],
	},
	"grants": [
		// Personal devices -> servers: HTTPS UI + Pocket ID auth (via Caddy).
		{"src": ["autogroup:member"], "dst": ["coruscant", "dathomir"], "ip": ["tcp:443"]},
		// Endor-only :22 network path (Tailscale SSH + plain-OpenSSH deploys).
		{"src": ["endor"], "dst": ["coruscant", "dathomir"], "ip": ["tcp:22"]},
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
		// check mode (12h): identity PLUS fresh IdP sign-in. Only SSH
		// mitigation until Tailscale patches Tailworm. BatchMode deploys FAIL
		// past expiry — re-auth in browser, re-run. autogroup:self REMOVED:
		// both servers are tagged, endor->servers rides the tag dsts.
		// users exactly root + nixos (nonroot would admit any Unix account).
		{
			"action": "check",
			"checkPeriod": "12h",
			"src": ["autogroup:member"],
			"dst": ["tag:machine", "tag:nixos-machine", "tag:server-ha", "tag:server-infra"],
			"users": ["root", "nixos"],
		},
	],
	"tests": [
		{"src": "endor", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443", "coruscant:22", "dathomir:22"]},
		{"src": "s23", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443"]},
		{"src": "coruscant", "proto": "tcp", "accept": ["dathomir:443"]},
		{"src": "dathomir", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443"]},
		{"src": "muse", "proto": "tcp", "accept": ["coruscant:443", "dathomir:443"]},
		{"src": "endor", "proto": "icmp", "accept": ["coruscant:0", "dathomir:0"]},
		// Full isolation (transitional grant gone): servers cannot initiate to
		// personal devices; raw :1411/:8090 closed to everyone; s23 and muse
		// have no :22 path.
		{"src": "endor", "deny": ["dathomir:1411", "dathomir:8090"]},
		{"src": "s23", "deny": ["dathomir:1411", "dathomir:8090", "coruscant:22", "dathomir:22"]},
		{"src": "coruscant", "deny": ["endor:443", "s23:443", "dathomir:1411", "dathomir:8090"]},
		{"src": "dathomir", "deny": ["endor:443", "s23:443", "dathomir:1411", "dathomir:8090"]},
		{"src": "muse", "deny": ["dathomir:1411", "dathomir:8090", "coruscant:22", "dathomir:22"]},
	],
	"sshTests": [
		{"src": "endor", "dst": ["coruscant", "dathomir"], "check": ["root", "nixos"]},
	],
}

EOF
}
