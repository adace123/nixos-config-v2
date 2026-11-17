_:
# Audiobookshelf: self-hosted audiobook and podcast server on dathomir,
# published tailnet-only as <audiobookshelf-domain> via the shared Caddy.
#
# The point of it here is the private podcast series: episodes are made
# elsewhere and uploaded to Audiobookshelf, which becomes the listening
# library (its own Android/iOS apps, progress sync, offline downloads,
# background playback). It is not a public podcast host — dathomir has no
# public IP, and the name resolves to a tailnet address, so a server-side
# fetcher such as Pocket Casts cannot reach it. The RSS feed Audiobookshelf
# can open per library item is only usable from a client already on the
# tailnet (the Audiobookshelf app, or AntennaPod on a phone with Tailscale).
#
# The service is the stock NixOS module (`services.audiobookshelf`): port
# 8000, bound to loopback only, Caddy the single tailnet path in — the same
# posture as the beszel hub, Pocket ID, Gatus and the wiki. No firewall
# opening: `trustedInterfaces = [ "tailscale0" ]` in the host module is the
# only path in.
#
# Libraries are created in the UI after the first deploy, not declaratively:
# a Podcast library pointing at /var/lib/audiobookshelf/podcasts, flat
# (one folder per show, episodes directly inside, no season folders).
# See docs/dathomir.md for the first-run steps and how Juno uploads.
{
  services.audiobookshelf = {
    enable = true;
    # Loopback only: Caddy is the only tailnet path in.
    host = "127.0.0.1";
    # NixOS default is 8000; stated explicitly so the Caddy vhost and this
    # module cannot drift apart silently. Free on dathomir (8090 beszel,
    # 1411 Pocket ID, 8088 Gatus, 8080 OpenKnowledge).
    port = 8000;
    # Path inside /var/lib: config and metadata live at
    # /var/lib/audiobookshelf, media under podcasts/ and audiobooks/.
    dataDir = "audiobookshelf";
  };

  # Media folders the service owns, so a library created in the UI has
  # somewhere to point at and an API/filesystem upload has somewhere to land.
  systemd.tmpfiles.rules = [
    "d /var/lib/audiobookshelf/podcasts 0750 audiobookshelf audiobookshelf -"
    "d /var/lib/audiobookshelf/audiobooks 0750 audiobookshelf audiobooks -"
  ];
}
