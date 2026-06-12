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
        reverse_proxy localhost:8123
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
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-8yZDrejNKsaUnUaTUFYbarWNmxafqp2z2rWo+XRsxV8=";
    };
    environmentFile = config.sops.templates."caddy-env".path;
  };

  systemd.services.caddy = { };
}
