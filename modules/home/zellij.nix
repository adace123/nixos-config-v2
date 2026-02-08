{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Zellij configuration and layouts
  zellijConfig = ''
    // Zellij Configuration
    // Documentation: https://zellij.dev/documentation/

    // ===== General Settings =====
    default_shell "zsh"
    default_layout "default"
    pane_frames true
    simplified_ui true
    default_mode "normal"
    mouse_mode true
    scroll_buffer_size 10000
    copy_command "pbcopy"  // macOS clipboard
    copy_clipboard "system"
    copy_on_select true
    scrollback_editor "nvim"
    mirror_session false
    // Try both paths for layouts
    layout_dir "${config.home.homeDirectory}/.config/zellij/layouts"

    // ===== UI Settings =====
    session_serialization false
    pane_viewport_serialization false
    scrollback_lines_to_serialize 0
    styled_underlines true

    // ===== Keybindings =====
    keybinds clear-defaults=true {
        normal {
            // Pane management
            bind "Alt h" { MoveFocus "Left"; }
            bind "Alt l" { MoveFocus "Right"; }
            bind "Alt j" { MoveFocus "Down"; }
            bind "Alt k" { MoveFocus "Up"; }
            bind "Alt n" { NewPane; }
            bind "Alt d" { NewPane "Right"; SwitchToMode "Normal"; }
            bind "Alt D" { NewPane "Down"; SwitchToMode "Normal"; }
            bind "Alt x" { CloseFocus; }
            bind "Alt f" { ToggleFocusFullscreen; }
            bind "Alt z" { TogglePaneFrames; }

            // Resize panes
            bind "Alt H" { Resize "Increase Left"; }
            bind "Alt L" { Resize "Increase Right"; }
            bind "Alt J" { Resize "Increase Down"; }
            bind "Alt K" { Resize "Increase Up"; }

            // Tab management
            bind "Alt t" { NewTab; SwitchToMode "Normal"; }
            bind "Alt w" { CloseTab; }
            bind "Alt [" { GoToPreviousTab; }
            bind "Alt ]" { GoToNextTab; }
            bind "Ctrl [" { GoToPreviousTab; }
            bind "Ctrl ]" { GoToNextTab; }
            bind "Alt 1" { GoToTab 1; }
            bind "Alt 2" { GoToTab 2; }
            bind "Alt 3" { GoToTab 3; }
            bind "Alt 4" { GoToTab 4; }
            bind "Alt 5" { GoToTab 5; }
            bind "Alt 6" { GoToTab 6; }
            bind "Alt 7" { GoToTab 7; }
            bind "Alt 8" { GoToTab 8; }
            bind "Alt 9" { GoToTab 9; }
            bind "Alt r" { SwitchToMode "RenameTab"; TabNameInput 0; }

            // Session management
            bind "Alt s" { SwitchToMode "Session"; }
            bind "Alt q" { Quit; }
            bind "Alt Q" { Detach; }

            // Scroll mode
            bind "Alt e" { EditScrollback; SwitchToMode "Normal"; }
            bind "Alt /" { SwitchToMode "Scroll"; }
            bind "PageUp" { PageScrollUp; }
            bind "PageDown" { PageScrollDown; }

            // Search
            bind "Ctrl f" { SwitchToMode "Search"; SearchInput 0; }

            // Tab switcher (floating with room plugin)
            bind "Ctrl Space" {
                LaunchOrFocusPlugin "file:~/.config/zellij/plugins/room.wasm" {
                    floating true
                    ignore_case true
                }
            }

            // Quick launch applications
            bind "Alt b" {
                Run "${pkgs.btop}/bin/btop" {
                    floating true
                    close_on_exit true
                    x "10%"
                    y "10%"
                    width "80%"
                    height "80%"
                }
            }
            bind "Alt k" {
                Run "${pkgs.k9s}/bin/k9s" {
                    floating true
                    close_on_exit true
                    x "10%"
                    y "10%"
                    width "80%"
                    height "80%"
                }
            }
            bind "Alt y" {
                Run "${pkgs.yazi}/bin/yazi" {
                    floating true
                    close_on_exit true
                    x "10%"
                    y "10%"
                    width "80%"
                    height "80%"
                }
            }
            bind "Alt a" {
                Run "${config.home.homeDirectory}/.local/bin/ai-selector" {
                    floating true
                    close_on_exit false
                    x "10%"
                    y "10%"
                    width "80%"
                    height "80%"
                }
            }

            // Floating pane toggle and create
            bind "Ctrl f" { ToggleFloatingPanes; }
            bind "Alt F" {
                NewPane {
                    floating true
                    x "10%"
                    y "10%"
                    width "80%"
                    height "80%"
                }
            }

            // Mode switching
            bind "Ctrl p" { SwitchToMode "Pane"; }
            bind "Ctrl t" { SwitchToMode "Tab"; }
            bind "Ctrl s" { SwitchToMode "Scroll"; }
            bind "Ctrl o" { SwitchToMode "Session"; }
            bind "Ctrl g" { SwitchToMode "Locked"; }
        }

        locked {
            bind "Ctrl g" { SwitchToMode "Normal"; }
        }

        pane {
            bind "Esc" { SwitchToMode "Normal"; }
            bind "h" { NewPane "Left"; SwitchToMode "Normal"; }
            bind "l" { NewPane "Right"; SwitchToMode "Normal"; }
            bind "j" { NewPane "Down"; SwitchToMode "Normal"; }
            bind "k" { NewPane "Up"; SwitchToMode "Normal"; }
            bind "Left" { MoveFocus "Left"; }
            bind "Right" { MoveFocus "Right"; }
            bind "Down" { MoveFocus "Down"; }
            bind "Up" { MoveFocus "Up"; }
            bind "n" { NewPane; SwitchToMode "Normal"; }
            bind "d" { CloseFocus; SwitchToMode "Normal"; }
            bind "x" { CloseFocus; SwitchToMode "Normal"; }
            bind "f" {
                NewPane {
                    floating true
                    x "10%"
                    y "10%"
                    width "80%"
                    height "80%"
                }
                SwitchToMode "Normal";
            }
            bind "z" { TogglePaneFrames; SwitchToMode "Normal"; }
            bind "w" { ToggleFloatingPanes; SwitchToMode "Normal"; }
            bind "e" { TogglePaneEmbedOrFloating; SwitchToMode "Normal"; }
            bind "r" { SwitchToMode "RenamePane"; PaneNameInput 0; }
        }

        tab {
            bind "Esc" { SwitchToMode "Normal"; }
            bind "n" { NewTab; SwitchToMode "Normal"; }
            bind "x" { CloseTab; SwitchToMode "Normal"; }
            bind "h" "Left" { GoToPreviousTab; }
            bind "l" "Right" { GoToNextTab; }
            bind "j" "Down" { GoToPreviousTab; }
            bind "k" "Up" { GoToNextTab; }
            bind "r" { SwitchToMode "RenameTab"; TabNameInput 0; }
            bind "1" { GoToTab 1; SwitchToMode "Normal"; }
            bind "2" { GoToTab 2; SwitchToMode "Normal"; }
            bind "3" { GoToTab 3; SwitchToMode "Normal"; }
            bind "4" { GoToTab 4; SwitchToMode "Normal"; }
            bind "5" { GoToTab 5; SwitchToMode "Normal"; }
            bind "6" { GoToTab 6; SwitchToMode "Normal"; }
            bind "7" { GoToTab 7; SwitchToMode "Normal"; }
            bind "8" { GoToTab 8; SwitchToMode "Normal"; }
            bind "9" { GoToTab 9; SwitchToMode "Normal"; }
            bind "Tab" { ToggleTab; }
        }

        scroll {
            bind "Esc" { SwitchToMode "Normal"; }
            bind "e" { EditScrollback; SwitchToMode "Normal"; }
            bind "Ctrl c" { ScrollToBottom; SwitchToMode "Normal"; }
            bind "j" "Down" { ScrollDown; }
            bind "k" "Up" { ScrollUp; }
            bind "Ctrl f" "PageDown" { PageScrollDown; }
            bind "Ctrl b" "PageUp" { PageScrollUp; }
            bind "d" { HalfPageScrollDown; }
            bind "u" { HalfPageScrollUp; }
            bind "Ctrl d" { HalfPageScrollDown; }
            bind "Ctrl u" { HalfPageScrollUp; }
            bind "/" { SwitchToMode "Search"; SearchInput 0; }
        }

        search {
            bind "Esc" { ScrollToBottom; SwitchToMode "Normal"; }
            bind "Ctrl c" { ScrollToBottom; SwitchToMode "Normal"; }
            bind "n" { Search "down"; }
            bind "N" { Search "up"; }
            bind "c" { SearchToggleOption "CaseSensitivity"; }
            bind "w" { SearchToggleOption "Wrap"; }
            bind "o" { SearchToggleOption "WholeWord"; }
        }

        session {
            bind "Esc" { SwitchToMode "Normal"; }
            bind "d" { Detach; }
            bind "q" { Quit; }
        }

        renametab {
            bind "Esc" { UndoRenameTab; SwitchToMode "Normal"; }
            bind "Enter" { SwitchToMode "Normal"; }
        }

        renamepane {
            bind "Esc" { UndoRenamePane; SwitchToMode "Normal"; }
            bind "Enter" { SwitchToMode "Normal"; }
        }
    }

    // ===== Plugins =====
    plugins {
        tab-bar { path "tab-bar"; }
        strider { path "strider"; }
        compact-bar { path "compact-bar"; }
    }
  '';

  defaultLayout = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="https://github.com/dj95/zjstatus/releases/latest/download/zjstatus.wasm" {
                    format_left   "{mode} #[fg=#89B4FA,bold]{session}"
                    format_center "{tabs}"
                    format_right  "#[fg=#49507a,bg=#89b4fa,bold] {command_weather} {datetime}"
                    format_space  ""

                    border_enabled  "false"
                    border_char     "─"
                    border_format   "#[fg=#6C7086]{char}"
                    border_position "top"

                    hide_frame_for_single_pane "true"

                    mode_normal  "#[bg=blue] "
                    mode_pane    "#[fg=purple] PANE "
                    mode_tab     "#[fg=red] TAB "
                    mode_resize  "#[fg=red] RESIZE "
                    mode_tmux    "#[bg=#ffc387] "

                    tab_normal   "#[fg=#6C7086] {name} "
                    tab_active   "#[fg=#9399B2,bold,italic] {name} "

                    // WEATHER
                    // the command that should be executed
                    command_weather_command "curl \"wttr.in/Los+Angeles?format=3\""
                    // themeing and format of the command
                    command_weather_format "{stdout}"
                    // interval in seconds, between two command runs
                    command_weather_interval "3600" // every hour
                    command_weather_rendermode "raw"

                    datetime        "#[fg=#6C7086,bold] {format} "
                    datetime_format "%A, %d %b %Y %I:%M %p"
                    datetime_timezone "America/Los_Angeles"
                }
            }
        }

        tab name="main" focus=true {
            pane
        }
    }
  '';

  devLayout = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="https://github.com/dj95/zjstatus/releases/latest/download/zjstatus.wasm" {
                    format_left   "{mode} #[fg=#89B4FA,bold]{session}"
                    format_center "{tabs}"
                    format_right  "#[fg=#49507a,bg=#89b4fa,bold] {command_weather} {datetime}"
                    format_space  ""

                    border_enabled  "false"
                    border_char     "─"
                    border_format   "#[fg=#6C7086]{char}"
                    border_position "top"

                    hide_frame_for_single_pane "true"

                    mode_normal  "#[bg=blue] "
                    mode_pane    "#[fg=purple] PANE "
                    mode_tab     "#[fg=red] TAB "
                    mode_resize  "#[fg=red] RESIZE "
                    mode_tmux    "#[bg=#ffc387] "

                    tab_normal   "#[fg=#6C7086] {name} "
                    tab_active   "#[fg=#9399B2,bold,italic] {name} "

                    // WEATHER
                    // the command that should be executed
                    command_weather_command "curl \"wttr.in/Los+Angeles?format=3\""
                    // themeing and format of the command
                    command_weather_format "{stdout}"
                    // interval in seconds, between two command runs
                    command_weather_interval "3600" // every hour
                    command_weather_rendermode "raw"

                    datetime        "#[fg=#6C7086,bold] {format} "
                    datetime_format "%A, %d %b %Y %I:%M %p"
                    datetime_timezone "America/Los_Angeles"
                }
            }
        }

        tab name="editor" focus=true {
            pane
        }

        tab name="terminal" {
            pane split_direction="vertical" {
                pane
                pane
            }
        }

        tab name="server" {
            pane
        }
    }
  '';

  splitLayout = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="https://github.com/dj95/zjstatus/releases/latest/download/zjstatus.wasm" {
                    format_left   "{mode} #[fg=#89B4FA,bold]{session}"
                    format_center "{tabs}"
                    format_right  "#[fg=#49507a,bg=#89b4fa,bold] {command_weather} {datetime}"
                    format_space  ""

                    border_enabled  "false"
                    border_char     "─"
                    border_format   "#[fg=#6C7086]{char}"
                    border_position "top"

                    hide_frame_for_single_pane "true"

                    mode_normal  "#[bg=blue] "
                    mode_pane    "#[fg=purple] PANE "
                    mode_tab     "#[fg=red] TAB "
                    mode_resize  "#[fg=red] RESIZE "
                    mode_tmux    "#[bg=#ffc387] "

                    tab_normal   "#[fg=#6C7086] {name} "
                    tab_active   "#[fg=#9399B2,bold,italic] {name} "

                    // WEATHER
                    // the command that should be executed
                    command_weather_command "curl \"wttr.in/Los+Angeles?format=3\""
                    // themeing and format of the command
                    command_weather_format "{stdout}"
                    // interval in seconds, between two command runs
                    command_weather_interval "3600" // every hour
                    command_weather_rendermode "raw"

                    datetime        "#[fg=#6C7086,bold] {format} "
                    datetime_format "%A, %d %b %Y %I:%M %p"
                    datetime_timezone "America/Los_Angeles"
                }
            }
        }

        tab name="main" focus=true {
            pane split_direction="vertical" {
                pane size="60%"
                pane size="40%" {
                    pane split_direction="horizontal" {
                        pane
                        pane
                    }
                }
            }
        }
    }
  '';
in
{
  # Install and configure zellij
  programs.zellij = {
    enable = true;
  };

  home.file = {
    # Standard XDG config path
    ".config/zellij/config.kdl".text = zellijConfig;
    ".config/zellij/layouts/default.kdl".text = defaultLayout;
    ".config/zellij/layouts/dev.kdl".text = devLayout;
    ".config/zellij/layouts/split.kdl".text = splitLayout;
    ".config/zellij/layouts/.keep".text = "";

    # macOS specific config path (some versions of zellij on macOS look here)
    "Library/Application Support/org.Zellij-Contributors.Zellij/config.kdl".text = zellijConfig;
    "Library/Application Support/org.Zellij-Contributors.Zellij/layouts/default.kdl".text =
      defaultLayout;
    "Library/Application Support/org.Zellij-Contributors.Zellij/layouts/dev.kdl".text = devLayout;
    "Library/Application Support/org.Zellij-Contributors.Zellij/layouts/split.kdl".text = splitLayout;
    "Library/Application Support/org.Zellij-Contributors.Zellij/layouts/.keep".text = "";
  };

  # Download room plugin using activation script to always get latest
  home.activation.downloadRoomPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p "$HOME/.config/zellij/plugins"
    if [ ! -f "$HOME/.config/zellij/plugins/room.wasm" ] || [ -n "''${VERBOSE:-}" ]; then
      $DRY_RUN_CMD ${pkgs.curl}/bin/curl -L -o "$HOME/.config/zellij/plugins/room.wasm" \
        "https://github.com/rvcas/room/releases/latest/download/room.wasm"
    fi
  '';

  # Shell aliases for Zellij
  programs.zsh.shellAliases = {
    zj = "zellij";
    zja = "zellij attach";
    zjl = "zellij list-sessions";
    zjk = "zellij kill-session";
    zjka = "zellij kill-all-sessions";
  };
}
