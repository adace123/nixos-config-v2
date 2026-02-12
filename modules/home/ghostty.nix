{ pkgs, ... }:

let
  zellijPath = "${pkgs.zellij}/bin/zellij";
in
{
  # Ghostty terminal emulator configuration
  # Ghostty is a fast, native, GPU-accelerated terminal emulator

  home.file.".config/ghostty/config".text = ''
    # Ghostty Configuration
    # Documentation: https://ghostty.org/docs

    # ===== Font Configuration =====
    font-family = "FiraCode Nerd Font"
    font-size = 13
    font-thicken = true

    # Font features (ligatures)
    font-feature = -calt
    font-feature = -liga
    font-feature = -dlig

    # ===== Theme and Colors =====
    # Theme: use built-in themes or specify colors manually
    # theme = light
    # theme = dark
    # Using manual colors below instead of theme

    # Tokyo Night color scheme
    background = 1a1b26
    foreground = c0caf5

    # Cursor colors
    cursor-color = c0caf5
    cursor-text = 1a1b26
    cursor-style = bar
    cursor-style-blink = true

    # Selection colors
    selection-background = 33467c
    selection-foreground = c0caf5

    # Normal colors
    palette = 0=#15161e
    palette = 1=#f7768e
    palette = 2=#9ece6a
    palette = 3=#e0af68
    palette = 4=#7aa2f7
    palette = 5=#bb9af7
    palette = 6=#7dcfff
    palette = 7=#a9b1d6

    # Bright colors
    palette = 8=#414868
    palette = 9=#f7768e
    palette = 10=#9ece6a
    palette = 11=#e0af68
    palette = 12=#7aa2f7
    palette = 13=#bb9af7
    palette = 14=#7dcfff
    palette = 15=#c0caf5

    # ===== Window Configuration =====
    window-padding-x = 8
    window-padding-y = 8
    window-padding-balance = true

    # Window decorations: true, false, or transparent
    window-decoration = true

    # Window opacity (0.0 to 1.0)
    background-opacity = 0.95
    background-blur-radius = 20

    # Resize in discrete increments
    resize-overlay = never

    # macOS specific window settings
    macos-non-native-fullscreen = false
    macos-titlebar-style = tabs
    macos-option-as-alt = true

    # ===== Terminal Features =====
    # Shell to use (empty = login shell)
    # Zellij disabled - using default shell
    # command = ${zellijPath} attach --create main
    shell-integration = detect
    shell-integration-features = sudo,title,no-cursor

    # Scrollback
    scrollback-limit = 10000

    # Mouse
    mouse-hide-while-typing = true

    # Copy on select
    copy-on-select = clipboard

    # Clipboard settings
    clipboard-read = allow
    clipboard-write = allow
    clipboard-trim-trailing-spaces = true

    # ===== Performance =====
    # GPU acceleration is always enabled in Ghostty

    # ===== Keybindings =====
    # Format: keybind = trigger>action

    # Tab management
    keybind = super+t=new_tab
    keybind = super+w=close_surface
    keybind = super+shift+left_bracket=previous_tab
    keybind = super+shift+right_bracket=next_tab
    keybind = super+1=goto_tab:1
    keybind = super+2=goto_tab:2
    keybind = super+3=goto_tab:3
    keybind = super+4=goto_tab:4
    keybind = super+5=goto_tab:5
    keybind = super+6=goto_tab:6
    keybind = super+7=goto_tab:7
    keybind = super+8=goto_tab:8
    keybind = super+9=goto_tab:9

    # Split panes
    keybind = super+d=new_split:right
    keybind = super+shift+d=new_split:down
    keybind = super+shift+w=close_surface

    # Navigate splits
    keybind = super+h=goto_split:left
    keybind = super+j=goto_split:bottom
    keybind = super+k=goto_split:top
    keybind = super+l=goto_split:right

    # Resize splits
    keybind = super+alt+h=resize_split:left,10
    keybind = super+alt+j=resize_split:down,10
    keybind = super+alt+k=resize_split:up,10
    keybind = super+alt+l=resize_split:right,10

    # Font size
    keybind = super+equal=increase_font_size:1
    keybind = super+minus=decrease_font_size:1
    keybind = super+0=reset_font_size

    # Copy/Paste
    keybind = super+c=copy_to_clipboard
    keybind = super+v=paste_from_clipboard

    # Search
    keybind = super+f=toggle_quick_terminal

    # Clear screen
    keybind = super+k=clear_screen

    # Fullscreen
    keybind = super+enter=toggle_fullscreen

    # Reload config
    keybind = super+comma=reload_config

    # ===== Advanced Settings =====
    # Command to run when clicking on URLs
    link-url = true

    # Bell (audio bell is default)
    # visual-bell setting has been removed in newer versions

    # Confirm before closing
    confirm-close-surface = false
    quit-after-last-window-closed = false

    # Working directory for new windows/tabs
    working-directory = inherit

    # Auto-update (macOS)
    auto-update = check
  '';

  # Shell aliases for Ghostty
  programs.zsh.shellAliases = {
    gt = "ghostty";
  };
}
