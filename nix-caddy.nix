# The Caddy build every host here uses: upstream Caddy plus the Cloudflare DNS
# plugin, which is what makes an ACME DNS-01 challenge possible for a host that has
# no inbound port 80 (dathomir) and for one whose certificate order must not depend
# on the router (the Pi hosts). Shared so the plugin version and its fixed-output
# hash live in one place — they have to be bumped together.
{ pkgs }:
pkgs.caddy.withPlugins {
  plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
  hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
}
