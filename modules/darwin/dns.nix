_: {
  # Cloudflare's resolvers for this Mac. macOS stores DNS per network service
  # rather than globally, so every enabled service gets them; the activation script
  # is idempotent, and re-running it simply re-asserts the setting.
  #
  # This coexists with Tailscale rather than fighting it. When Tailscale is managing
  # DNS it answers tailnet names itself and forwards everything else to whatever the
  # service is configured with — so this becomes the upstream that reaches the
  # public internet, and `dathomir-1` and other tailnet names still resolve.
  #
  # Applied at activation so `just switch` is the only step needed to change it.
  system.activationScripts.dns-resolvers.text = ''
    /usr/sbin/networksetup -listallnetworkservices \
      | tail -n +2 | grep -v '^\*' \
      | while IFS= read -r service; do
          /usr/sbin/networksetup -setdnsservers "$service" 1.1.1.1 1.0.0.1 || true
        done
  '';
}
