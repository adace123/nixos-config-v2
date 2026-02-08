{pkgs, ...}: {
  # Completion - using blink.cmp
  programs.nvf.settings.vim.autocomplete.blink-cmp = {
    enable = true;
    setupOpts = {
      keymap = {
        preset = "default";
        "<C-space>" = [
          "show"
          "show_documentation"
          "hide_documentation"
        ];
        "<C-e>" = ["hide"];
        "<CR>" = [
          "accept"
          "fallback"
        ];
        "<Tab>" = [
          "select_next"
          "fallback"
        ];
        "<S-Tab>" = [
          "select_prev"
          "fallback"
        ];
        "<C-k>" = [
          "select_prev"
          "fallback"
        ];
        "<C-j>" = [
          "select_next"
          "fallback"
        ];
      };
      sources = {
        default = [
          "lsp"
          "path"
          "buffer"
        ];
      };
      cmdline = {
        keymap = {
          preset = "inherit";
          "<CR>" = ["fallback"];
        };
        completion = {
          menu = {
            auto_show = true;
          };
          list = {
            selection = {
              preselect = true;
              auto_insert = true;
            };
          };
        };
      };

      completion = {
        trigger = {
          show_on_insert_on_trigger_character = true;
        };

        menu = {
          enabled = true;
          auto_show = true;
          draw = {
            columns = [
              ["kind_icon"]
              [
                "label"
                "label_description"
              ]
              ["source_name"]
            ];
          };
        };
        documentation = {
          auto_show = true;
          auto_show_delay_ms = 500;
        };
      };
    };
  };
}
