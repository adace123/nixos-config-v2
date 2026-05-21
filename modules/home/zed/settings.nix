{ pkgs, ... }:
{
  programs.zed-editor.userSettings = {
    which_key = {
      enabled = true;
      delay_ms = 500;
    };
    theme = {
      mode = "system";
      dark = "Catppuccin Mocha";
      light = "Catppuccin Latte";
    };

    vim_mode = true;

    ui_font_size = 14;
    buffer_font_size = 13;
    buffer_font_family = "FiraCode Nerd Font";

    terminal = {
      font_family = "FiraCode Nerd Font";
      font_size = 13;
    };

    format_on_save = "on";
    languages = {
      Nix = {
        format_on_save = "on";
        language_servers = [
          "!nixd"
          "nil"
        ];
        formatter.external = {
          command = "${pkgs.nixfmt}/bin/nixfmt";
          arguments = [
            "--quiet"
            "--"
          ];
        };
      };
      Python = {
        format_on_save = "on";
        formatter.external = {
          command = "${pkgs.ruff}/bin/ruff";
          arguments = [
            "format"
            "--stdin-filename"
            "{buffer_path}"
          ];
        };
      };
    };

    collaboration_panel = {
      button = true;
    };

    git = {
      git_gutter = "tracked_files";
    };

    agent = {
      enabled = true;
      version = "2";
      commit_message_model = {
        provider = "copilot_chat";
        model = "gpt-5-mini";
      };
      inline_assistant_model = {
        provider = "copilot_chat";
        model = "gpt-5-mini";
      };
    };

    tab_size = 2;
    hard_tabs = false;
    tabs.file_icons = true;
    tabs.show_diagnostics = "errors";

    indent_guides = {
      enabled = true;
      line_width = 1;
      active_line_width = 1;
      coloring = "indent_aware";
    };

    inlay_hints = {
      enabled = true;
      show_type_hints = true;
      show_parameter_hints = true;
      show_other_hints = true;
    };

    cursor = {
      shape = "bar";
      show_multi_insert_cursor_guide = true;
    };
  };
}
