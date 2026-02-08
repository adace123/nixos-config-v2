{ pkgs, ... }:
{
  home = {
    packages = with pkgs; [
      fastfetch
    ];

    file = {
      # Clean, modern fastfetch configuration
      ".config/fastfetch/config.jsonc".text = ''
        {
          "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
          "logo": {
            "type": "builtin",
            "source": "macos_small",
            "padding": {
              "top": 1,
              "left": 3,
              "right": 2
            }
          },
          "display": {
            "separator": "  ",
            "color": {
              "keys": "cyan",
              "output": "white"
            }
          },
          "modules": [
            {
              "type": "title",
              "key": "   ",
              "keyColor": "blue"
            },
            {
              "type": "separator"
            },
            {
              "type": "os",
              "key": " 󰀵 OS",
              "keyColor": "blue"
            },
            {
              "type": "host",
              "key": " 󰇅 Host",
              "keyColor": "green"
            },
            {
              "type": "kernel",
              "key": "   Kernel",
              "keyColor": "yellow"
            },
            {
              "type": "uptime",
              "key": " 󰅐 Uptime",
              "keyColor": "magenta"
            },
            {
              "type": "packages",
              "key": " 󰏗 Packages",
              "keyColor": "cyan"
            },
            {
              "type": "shell",
              "key": "   Shell",
              "keyColor": "red"
            },
            {
              "type": "terminal",
              "key": "   Term",
              "keyColor": "blue"
            },
            {
              "type": "separator"
            },
            {
              "type": "cpu",
              "key": " 󰻠 CPU",
              "keyColor": "green"
            },
            {
              "type": "gpu",
              "key": " 󰍛 GPU",
              "keyColor": "yellow"
            },
            {
              "type": "memory",
              "key": "   Memory",
              "keyColor": "magenta"
            },
            {
              "type": "disk",
              "key": " 󰋊 Disk",
              "keyColor": "cyan"
            },
            {
              "type": "separator"
            },
            {
              "type": "colors",
              "paddingLeft": 3,
              "symbol": "circle"
            }
          ]
        }
      '';

      # Minimal configuration (can switch with: fastfetch -c minimal)
      ".config/fastfetch/minimal.jsonc".text = ''
        {
          "logo": {
            "type": "builtin",
            "source": "macos_small"
          },
          "display": {
            "separator": " → "
          },
          "modules": [
            "title",
            "os",
            "kernel",
            "uptime",
            "shell",
            "terminal",
            "cpu",
            "memory",
            "colors"
          ]
        }
      '';

      # Full detailed configuration
      ".config/fastfetch/full.jsonc".text = ''
        {
          "logo": {
            "type": "builtin",
            "source": "macos"
          },
          "display": {
            "separator": "  ",
            "color": "blue"
          },
          "modules": [
            {
              "type": "title",
              "format": "{user-name}@{host-name}"
            },
            "separator",
            "os",
            "host",
            "kernel",
            "uptime",
            "packages",
            "shell",
            "display",
            "de",
            "wm",
            "wmtheme",
            "theme",
            "icons",
            "font",
            "cursor",
            "terminal",
            "terminalfont",
            "cpu",
            "gpu",
            "memory",
            "swap",
            "disk",
            "localip",
            "battery",
            "locale",
            "break",
            "colors"
          ]
        }
      '';
    };
  };
}
