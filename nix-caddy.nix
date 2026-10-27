# The Caddy build every host here uses: upstream Caddy plus the Cloudflare DNS
# plugin, which is what makes an ACME DNS-01 challenge possible for a host that has
# no inbound port 80 (dathomir) and for one whose certificate order must not depend
# on the router (the Pi hosts). Shared so the plugin version and its fixed-output
# hash live in one place — they have to be bumped together.
#
# The hash was refreshed 2026-10-16: a fresh build (dathomir) failed with a hash
# mismatch for caddy 2.11.7 + caddy-dns/cloudflare@v0.2.4 — the fetch of those
# pinned sources no longer produces the old content. Existing stores kept working
# because a fixed-output derivation's old path still resolves, which is why this
# only surfaced on a host that had never built it. Anywhere building this afresh
# would have failed the same way.
#
# Refreshed again 2026-10-26: the flake.lock update moved nixpkgs (newer Go
# toolchain changes the vendored module graph), so the same pinned sources
# hash differently. Adopted the builder-reported content hash.
{ pkgs }:
pkgs.caddy.withPlugins {
  plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
  hash = "sha256-tubXIDCJnO2mvdnPlZclwDhNGaeeYLSt7lnni3+pXDo=";
}
