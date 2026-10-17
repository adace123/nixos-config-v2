{ config, pkgs, ... }:
{
  sops.secrets.cloudflare-api-key = { };

  sops.templates."caddy-env" = {
    content = ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder.cloudflare-api-key}
    '';
    owner = "caddy";
    group = "caddy";
    mode = "0400";
  };

  sops.templates."caddyfile" = {
    content = ''
      {
        acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      }

      ${config.sops.placeholder.home-assistant-external-domain} {
        reverse_proxy 127.0.0.1:8123
      }
    '';
    owner = "caddy";
    group = "caddy";
    mode = "0400";
  };

  services.caddy = {
    enable = true;
    openFirewall = true;
    configFile = config.sops.templates."caddyfile".path;
    # Shared with dathomir's config so the Cloudflare DNS plugin (and its hash)
    # is defined once — see nix-caddy.nix.
    package = import ../../nix-caddy.nix { inherit pkgs; };
    environmentFile = config.sops.templates."caddy-env".path;
  };

  systemd.services.caddy.restartTriggers = [
    config.sops.secrets.cloudflare-api-key.path
    config.sops.secrets.home-assistant-external-domain.path
    # Secret paths above only fire when a *value* changes. A sops template is
    # rewritten on every activation but keeps the same path, so editing the
    # Caddyfile would otherwise be invisible to systemd and Caddy would keep serving
    # the old config. This store path is keyed by the template's text, so it changes
    # exactly when the Caddyfile does.
    (pkgs.writeText "caddyfile-source" config.sops.templates."caddyfile".content)
  ];
}
