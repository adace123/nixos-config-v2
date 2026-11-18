{ inputs, pkgs, ... }:
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
    "d /var/lib/audiobookshelf/audiobooks 0750 audiobookshelf audiobookshelf -"
  ];

  # Per-episode cover artwork, which upstream 2.37.2 has no support for
  # (advplyr/audiobookshelf#1573). This builds github:adace123/audiobookshelf
  # instead of the official package: upstream v2.37.2 plus
  # advplyr/audiobookshelf#5699 (server: podcastEpisodes.coverPath/imageURL,
  # embedded-art extraction in the podcast scanner,
  # GET /api/podcasts/:id/episode/:episodeId/cover with a 302 fallback to the
  # show cover) and the web-client half that PR leaves out — the episode view,
  # the episode rows and the player now show the episode's own image.
  #
  # The version bump to 2.38.0 is load-bearing, not cosmetic: MigrationManager
  # skips migrations when the server version equals the recorded database
  # version, so the bundled v2.38.0-add-episode-cover migration would never run
  # against a 2.37.2 database. Note the database version is then 2.38.0, which
  # is ahead of upstream — when upstream ships its own 2.38.0, re-check its
  # migrations against this one before switching back to the official package.
  #
  # Both npmDepsHash pins stay valid: the fork touches neither
  # package-lock.json. Overriding `src` is enough because nixpkgs threads
  # `finalAttrs`, so the client derivation is rebuilt from the same source.
  services.audiobookshelf.package = pkgs.audiobookshelf.overrideAttrs (old: {
    version = "2.38.0";
    # Source from the audiobookshelf-fork flake input (flake.lock pins the
    # resolved rev and narHash), so updating is `just update-input
    # audiobookshelf-fork` after pushing commits to the branch — no rev/hash
    # edits here. client.nix reads src.name (for sourceRoot "${src.name}/client"),
    # which a fetched-source input lacks: name it without adding a hash to it.
    src = pkgs.runCommand "audiobookshelf-fork-source" { } ''
      cp -r ${inputs.audiobookshelf-fork} $out
    '';
    # Upstream's changelog link interpolates src.tag, which a rev-based fetch
    # does not carry.
    meta = (old.meta or { }) // {
      changelog = "https://github.com/adace123/audiobookshelf/commits/fork-2.37.2-episode-covers";
    };
  });
}
