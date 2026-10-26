# ── DNS for the three tailnet-only services ──────────────────────────────────
#
# All records point at Tailscale addresses (100.64.0.0/10) instead of public
# ones, and are DNS-only (`proxied = false`). That is the whole trick: the name
# resolves from anywhere, but the address it resolves to is only routable from
# inside the tailnet — so HA, the beszel dashboard, Pocket ID, and Gatus are
# reachable over Tailscale without any host exposing anything. Cloudflare's proxy
# could not reach a 100.x address anyway, and in front of Caddy it would fight
# the ACME DNS-01 challenge.
# HA and beszel records already existed and were imported rather than recreated:
#   tofu import cloudflare_dns_record.home_assistant '<zone-id>/<record-id>'
#   tofu import cloudflare_dns_record.beszel '<zone-id>/<record-id>'

resource "cloudflare_dns_record" "home_assistant" {
  zone_id = var.cloudflare_zone_id
  name    = var.home_assistant_domain
  type    = "A"
  content = var.home_assistant_tailnet_ip
  ttl     = 1 # automatic
  proxied = false
  comment = "Home Assistant on coruscant — Tailscale-only by design (managed by OpenTofu, nixos-config-v2)"
}

# Pocket ID, the passkey identity provider the hub delegates its logins to. Same
# tailnet-only treatment, and new rather than imported — nothing served this name
# before.
resource "cloudflare_dns_record" "pocket_id" {
  zone_id = var.cloudflare_zone_id
  name    = var.pocket_id_domain
  type    = "A"
  content = var.dathomir_tailnet_ip
  ttl     = 1 # automatic
  proxied = false
  comment = "Pocket ID on dathomir — Tailscale-only by design (managed by OpenTofu, nixos-config-v2)"
}

# The hub moved from the Pi hosts to dathomir, so this record now points at
# dathomir's tailnet address. Repointing it takes the name away from the hub that
# still runs on the Pi hosts, whatever else the old one was serving.
resource "cloudflare_dns_record" "beszel" {
  zone_id = var.cloudflare_zone_id
  name    = var.beszel_domain
  type    = "A"
  content = var.dathomir_tailnet_ip
  ttl     = 1 # automatic
  proxied = false
  comment = "Beszel hub on dathomir — Tailscale-only by design (managed by OpenTofu, nixos-config-v2)"
}

# Gatus, the endpoint-monitoring status page. Same tailnet-only treatment as the
# hub and Pocket ID, served from dathomir.
resource "cloudflare_dns_record" "gatus" {
  zone_id = var.cloudflare_zone_id
  name    = var.gatus_domain
  type    = "A"
  content = var.dathomir_tailnet_ip
  ttl     = 1 # automatic
  proxied = false
  comment = "Gatus status page on dathomir — Tailscale-only by design (managed by OpenTofu, nixos-config-v2)"
}
