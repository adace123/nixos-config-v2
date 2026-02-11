{ pkgs, ... }:

{
  programs.zed-editor = {
    enable = true;

    # Extensions are managed via programs.zed-editor-extensions below
    # for better Nix integration and caching

    extraPackages = with pkgs; [
      nixd
      nil
      alejandra
      nodejs
    ];

    userSettings = {
      # Theme settings
      theme = {
        mode = "system";
        dark = "Catppuccin Mocha";
        light = "Catppuccin Latte";
      };

      # Editor settings
      vim_mode = true;
      hour_format = "hour24";

      # UI settings
      ui_font_size = 14;
      buffer_font_size = 13;
      buffer_font_family = "FiraCode Nerd Font";

      # Terminal settings
      terminal = {
        font_family = "FiraCode Nerd Font";
        font_size = 13;
      };

      # Language settings
      languages = {
        Nix = {
          language_servers = [
            "nixd"
            "!nil"
          ];
          formatter = {
            external = {
              command = "alejandra";
              arguments = [ "-" ];
            };
          };
        };
      };

      # LSP settings
      lsp = {
        nixd = {
          settings = {
            formatting = {
              command = [
                "alejandra"
                "-"
              ];
            };
          };
        };
      };

      # Collaboration settings
      collaboration_panel = {
        button = true;
      };

      # Assistant settings
      assistant = {
        enabled = true;
        version = "2";
      };

      # Git settings
      git = {
        git_gutter = "tracked_files";
      };

      # File settings
      autosave = "on_focus_change";

      # Tab settings
      tab_size = 2;
      hard_tabs = false;

      # Indentation guides
      indent_guides = {
        enabled = true;
        line_width = 1;
        active_line_width = 1;
        coloring = "fixed";
        background_coloring = "disabled";
      };

      # Inlay hints
      inlay_hints = {
        enabled = true;
        show_type_hints = true;
        show_parameter_hints = true;
        show_other_hints = true;
      };

      # Status bar
      status_bar = {
        show_copilot_icon = true;
      };
    };

    userKeymaps = [
      # Terminal toggle
      {
        context = "Workspace";
        bindings = {
          "ctrl-/" = "workspace::ToggleBottomDock";
        };
      }

      # Window/pane navigation (Ctrl+h/j/k/l like Neovim)
      {
        context = "Dock || Terminal || Editor";
        bindings = {
          "ctrl-h" = "workspace::ActivatePaneLeft";
          "ctrl-l" = "workspace::ActivatePaneRight";
          "ctrl-k" = "workspace::ActivatePaneUp";
          "ctrl-j" = "workspace::ActivatePaneDown";
        };
      }

      # Git panel
      {
        context = "GitPanel";
        bindings = {
          "q" = "git_panel::Close";
        };
      }

      # Agent/AI panel
      {
        context = "AgentPanel";
        bindings = {
          "ctrl-\\" = "workspace::ToggleRightDock";
          "cmd-k" = "workspace::ToggleRightDock";
        };
      }

      # Project panel (file explorer) - vim-like navigation
      {
        context = "ProjectPanel && not_editing";
        bindings = {
          "a" = "project_panel::NewFile";
          "A" = "project_panel::NewDirectory";
          "r" = "project_panel::Rename";
          "d" = "project_panel::Delete";
          "x" = "project_panel::Cut";
          "c" = "project_panel::Copy";
          "p" = "project_panel::Paste";
          "q" = "workspace::ToggleLeftDock";
          "space e" = "workspace::ToggleLeftDock";
          ":" = "command_palette::Toggle";
          "%" = "project_panel::NewFile";
          "/" = "project_panel::NewSearchInDirectory";
          "enter" = "project_panel::OpenPermanent";
          "escape" = "project_panel::ToggleFocus";
          "h" = "project_panel::CollapseSelectedEntry";
          "j" = "menu::SelectNext";
          "k" = "menu::SelectPrevious";
          "l" = "project_panel::ExpandSelectedEntry";
          "o" = "project_panel::OpenPermanent";
          "shift-d" = "project_panel::Delete";
          "shift-r" = "project_panel::Rename";
          "t" = "project_panel::OpenPermanent";
          "v" = "project_panel::OpenPermanent";
          "shift-g" = "menu::SelectLast";
          "g g" = "menu::SelectFirst";
          "-" = "project_panel::SelectParent";
          "ctrl-6" = "pane::AlternateFile";
        };
      }

      # Empty pane bindings (when no active editor)
      {
        context = "EmptyPane || SharedScreen";
        bindings = {
          "space space" = "file_finder::Toggle";
          "space f n" = "workspace::NewFile";
          "space f p" = "projects::OpenRecent";
          "space s g" = "workspace::NewSearch";
          "space q q" = "zed::Quit";
        };
      }

      # Main vim control bindings with space leader
      {
        context = "Editor && VimControl && !VimWaiting && !menu";
        bindings = {
          # Refactoring
          "space c r" = "editor::Rename";

          # AI/Assistant
          "space a a" = "assistant::ToggleFocus";
          "ctrl-\\" = "workspace::ToggleRightDock";
          "cmd-k" = "workspace::ToggleRightDock";
          "space a e" = "assistant::InlineAssist";
          "cmd-l" = "assistant::InlineAssist";
          "space a t" = "workspace::ToggleRightDock";

          # Git operations
          "space g g" = [
            "task::Spawn"
            {
              "task_name" = "lazygit";
              "reveal_target" = "center";
            }
          ];
          "space g h d" = "editor::ExpandAllDiffHunks";
          "space g h D" = "git::Diff";
          "space g h r" = "git::Restore";
          "space g h R" = "git::RestoreFile";
          "space g b" = "git::Blame";

          # UI toggles
          "space u i" = "editor::ToggleInlayHints";
          "space u w" = "editor::ToggleSoftWrap";

          # Markdown preview
          "space m p" = "markdown::OpenPreview";
          "space m P" = "markdown::OpenPreviewToTheSide";

          # Recent projects
          "space f p" = "projects::OpenRecent";

          # Search
          "space s w" = "buffer_search::Deploy";
          "space s W" = "pane::DeploySearch";
          "space s g" = "workspace::NewSearch";
          "space /" = "workspace::NewSearch";
          "space s b" = "vim::Search";

          # Buffer/Tab management (like harpoon)
          "space 1" = [
            "pane::ActivateItem"
            0
          ];
          "space 2" = [
            "pane::ActivateItem"
            1
          ];
          "space 3" = [
            "pane::ActivateItem"
            2
          ];
          "space 4" = [
            "pane::ActivateItem"
            3
          ];
          "space 5" = [
            "pane::ActivateItem"
            4
          ];
          "space 6" = [
            "pane::ActivateItem"
            5
          ];
          "space 7" = [
            "pane::ActivateItem"
            6
          ];
          "space 8" = [
            "pane::ActivateItem"
            7
          ];
          "space 9" = [
            "pane::ActivateItem"
            8
          ];
          "space 0" = "pane::ActivateLastItem";
          "] b" = "pane::ActivateNextItem";
          "[ b" = "pane::ActivatePreviousItem";
          "space ," = "tab_switcher::Toggle";

          # Buffer operations
          "space b b" = "pane::AlternateFile";
          "space b d" = "pane::CloseActiveItem";
          "space b q" = "pane::CloseInactiveItems";
          "space b n" = "workspace::NewFile";

          # File operations (Telescope-like)
          "space f f" = "file_finder::Toggle";
          "space space" = "file_finder::Toggle";
          "space f n" = "workspace::NewFile";

          # File explorer
          "space e" = "workspace::ToggleLeftDock";

          # Terminal
          "space t" = "workspace::ToggleBottomDock";

          # Window/pane management
          "space w s" = "pane::SplitDown";
          "space w v" = "pane::SplitRight";
          "space -" = "pane::SplitDown";
          "space |" = "pane::SplitRight";
          "space w c" = "pane::CloseAllItems";
          "space w d" = "pane::CloseAllItems";

          # LSP & Code actions
          "space c a" = "editor::ToggleCodeActions";
          "space s d" = "diagnostics::Deploy";
          "space s s" = "outline::Toggle";
          "space c f" = "editor::Format";

          # Navigation (hunks)
          "] h" = "editor::GoToHunk";
          "[ h" = "editor::GoToPreviousHunk";
          "] c" = "editor::GoToHunk";
          "[ c" = "editor::GoToPreviousHunk";

          # Navigation (diagnostics)
          "] d" = "editor::GoToDiagnostic";
          "[ d" = "editor::GoToPreviousDiagnostic";
          "] e" = "editor::GoToDiagnostic";
          "[ e" = "editor::GoToPreviousDiagnostic";

          # Excerpts
          "] q" = "editor::MoveToStartOfNextExcerpt";
          "[ q" = "editor::MoveToStartOfExcerpt";

          # Quit
          "space q q" = "zed::Quit";

          # Find all references
          "g r" = "editor::FindAllReferences";
        };
      }

      # Visual mode bindings
      {
        context = "Editor && vim_mode == visual && !VimWaiting && !VimObject";
        bindings = {
          # Move lines up/down (like Neovim's Alt+j/k)
          "shift-j" = "editor::MoveLineDown";
          "shift-k" = "editor::MoveLineUp";
        };
      }

      # Center cursor on scroll and search (like Neovim's zz)
      {
        context = "VimControl && !menu";
        bindings = {
          "ctrl-d" = [
            "workspace::SendKeystrokes"
            "ctrl-d z z"
          ];
          "ctrl-u" = [
            "workspace::SendKeystrokes"
            "ctrl-u z z"
          ];
          "n" = [
            "workspace::SendKeystrokes"
            "n z z z v"
          ];
          "shift-n" = [
            "workspace::SendKeystrokes"
            "shift-n z z z v"
          ];
          "shift-g" = [
            "workspace::SendKeystrokes"
            "shift-g z z"
          ];
        };
      }

      # Git operator bindings
      {
        context = "vim_operator == d";
        bindings = {
          "o" = "editor::ExpandAllDiffHunks";
          "r" = "git::Restore";
        };
      }

      # Sneak-like navigation
      {
        context = "vim_mode == normal || vim_mode == visual";
        bindings = {
          "s" = "vim::PushSneak";
          "S" = "vim::PushSneakBackward";
        };
      }

      # Any brackets text object
      {
        context = "vim_operator == a || vim_operator == i || vim_operator == cs";
        bindings = {
          "b" = "vim::AnyBrackets";
        };
      }
    ];
    # Global tasks available in all projects
    userTasks = [
      {
        label = "lazygit";
        command = "${pkgs.lazygit}/bin/lazygit";
        args = [
          "-p"
          "$ZED_WORKTREE_ROOT"
        ];
        use_new_terminal = true;
        allow_concurrent_runs = false;
        reveal = "always";
        hide = "on_success";
      }
    ];
  };

  # Extensions via nix-zed-extensions
  # Provides declarative, cached extension installation
  programs.zed-editor-extensions = {
    enable = true;
    packages = with pkgs.zed-extensions; [
      nix
      toml
      git-firefly
      opencode
      catppuccin
      catppuccin-icons
    ];
  };

  # Shell aliases for Zed
  programs.zsh.shellAliases = {
    zed = "zeditor";
  };
}
