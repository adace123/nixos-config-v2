{
  inputs,
  lib,
  ...
}:

# OmniWM — a macOS tiling window manager with Niri-style scrolling columns.
# Replaces AeroSpace (see the Window Management section of docs/darwin.md).
#
# The module imported below is *not* the one home-manager ships. OmniWM rejects
# any `settings.toml` that is not its complete schema, and the stock module
# writes exactly the attrset it is given, so partial settings there are silently
# dropped at runtime. inputs.omniwm.homeManagerModules.default deep-merges these
# settings over a full defaults file generated from the packaged version, merges
# `hotkeys` per id, and fails evaluation on an id the packaged OmniWM does not
# know — turning that silent rejection into a build error.
#
# Consequences worth knowing:
#   * Every key set here is owned by this file. OmniWM rewrites settings.toml
#     from its GUI, and the module deploys a writable copy that is regenerated
#     whenever the values differ, so GUI edits to these keys do not stick.
#   * Display-dependent settings (preserveSettings below) are taken from the live
#     file instead, because a committed display UUID would be wrong on the next
#     desk or monitor.
let
  omniwmLib = inputs.omniwm.lib;

  # OmniWM's shipped minimum sizes for apps with known resize floors. Declaring
  # `appRules` replaces OmniWM's list wholesale instead of extending it, so they
  # are reproduced here; values are from the packaged version's
  # settings-defaults.toml.
  floor = minWidth: minHeight: { inherit minWidth minHeight; };

  # bundleId -> rule body. Floors are OmniWM's own; `assignToWorkspace` and
  # `layout = "float"` mirror the AeroSpace on-window-detected rules this file
  # replaces — browsers on 1, terminals on 2, editors on 3, chat on 4, media on
  # 5, and the four windows that were floated rather than tiled.
  appRules = {
    # Upstream defaults, reproduced verbatim.
    "com.openai.codex" = floor 800.0 600.0;
    "com.eltima.cmd1.pro.mas" = floor 950.0 550.0;
    "com.apple.Safari" = floor 574.0 220.0;
    "app.zen-browser.zen" = floor 500.0 495.0;
    "company.thebrowser.dia" = floor 500.0 420.0;
    "com.microsoft.Outlook" = floor 930.0 650.0;
    "com.apple.MobileSMS" = floor 660.0 320.0;

    # Browsers — workspace 1.
    "com.google.Chrome" = (floor 500.0 375.0) // {
      assignToWorkspace = "1";
    };
    "org.mozilla.firefox" = (floor 500.0 120.0) // {
      assignToWorkspace = "1";
    };
    "company.thebrowser.Browser" = {
      assignToWorkspace = "1";
    };

    # Terminals — workspace 2.
    "com.mitchellh.ghostty" = (floor 90.0 48.0) // {
      assignToWorkspace = "2";
    };
    "com.apple.Terminal" = {
      assignToWorkspace = "2";
    };
    "com.googlecode.iterm2" = {
      assignToWorkspace = "2";
    };
    "net.kovidgoyal.kitty" = {
      assignToWorkspace = "2";
    };
    "io.alacritty" = {
      assignToWorkspace = "2";
    };

    # Editors and IDEs — workspace 3.
    "dev.zed.Zed" = (floor 360.0 240.0) // {
      assignToWorkspace = "3";
    };
    "com.microsoft.VSCode" = {
      assignToWorkspace = "3";
    };
    "com.todesktop.230313mzl4w4u92" = {
      assignToWorkspace = "3";
    };

    # Chat and calls — workspace 4.
    "com.hnc.Discord" = (floor 800.0 500.0) // {
      assignToWorkspace = "4";
    };
    "com.tinyspeck.slackmacgap" = {
      assignToWorkspace = "4";
    };
    "us.zoom.xos" = {
      assignToWorkspace = "4";
    };

    # Music — workspace 5.
    "com.spotify.client" = (floor 800.0 600.0) // {
      assignToWorkspace = "5";
    };

    # Floated rather than tiled: settings sheets, inspectors and pickers are not
    # useful as scrolling columns.
    "com.apple.systempreferences" = {
      layout = "float";
    };
    "com.apple.ActivityMonitor" = {
      layout = "float";
    };
    "com.apple.finder" = {
      layout = "float";
    };
    "com.1password.1password" = {
      layout = "float";
    };
  };
in
{
  imports = [ inputs.omniwm.homeManagerModules.default ];

  programs.omniwm = {
    enable = true;

    # `package` is deliberately left unset. The input packages OmniWM itself and
    # generates its defaults template from that version, so pointing this at
    # nixpkgs' copy would merge one version's schema onto another version's
    # binary.

    # Nix owns the binary, so OmniWM's own update check has nothing to do and
    # only reports versions this system will never run. The layout stays Niri —
    # scrolling columns, rather than the tiles/accordion pair AeroSpace had.
    settings.general = {
      updateChecksEnabled = false;
      defaultLayoutType = "niri";
    };

    # AeroSpace's gap geometry: 8pt between windows, 8pt at every screen edge.
    # OmniWM ships 16pt inner gaps and no outer gaps.
    settings.gaps = {
      size = 8.0;
      outer = {
        left = 8.0;
        right = 8.0;
        top = 8.0;
        bottom = 8.0;
      };
    };

    # AeroSpace had no drop-down terminal, and OmniWM's binds Option+` by
    # default. Flip this to true to get its Ghostty-backed quake terminal.
    settings.quakeTerminal.enabled = false;

    # Ten workspaces named 1–10, assigned to the main display except 6 and 7 on
    # the secondary one — the same shape OmniWM ships, plus the tenth workspace
    # AeroSpace's alt-0 bound. Roles are used rather than display UUIDs so
    # swapping monitors needs no change here.
    settings.workspaces = omniwmLib.workspaces [
      { }
      { }
      { }
      { }
      { }
      {
        displayName = "❤️";
        monitorAssignment.type = "secondary";
      }
      {
        displayName = "🚀";
        monitorAssignment.type = "secondary";
      }
      { }
      { }
      { }
    ];

    settings.appRules = lib.mapAttrsToList omniwmLib.appRule appRules;

    # Only the bindings that differ from OmniWM's defaults. Resize is not listed
    # because OmniWM already matches AeroSpace there: Option+Plus/Minus resizes
    # the focused column and Option+Shift+Plus/Minus the window inside it, where
    # AeroSpace's `resize smart ±50` did both at once.
    settings.hotkeys = omniwmLib.hotkeys {
      # AeroSpace's focus keys, in place of OmniWM's Option+Arrow defaults.
      "focus.left" = "Option+H";
      "focus.down" = "Option+J";
      "focus.up" = "Option+K";
      "focus.right" = "Option+L";

      # …and its move keys, likewise in place of Option+Shift+Arrow.
      "move.left" = "Option+Shift+H";
      "move.down" = "Option+Shift+J";
      "move.up" = "Option+Shift+K";
      "move.right" = "Option+Shift+L";

      # AeroSpace's alt-tab switched to the previous workspace. OmniWM gives
      # that action Control+Option+Tab and binds Option+Tab to the previous
      # *window*; since one shortcut can only drive one action, focusPrevious
      # gives up its default to keep the AeroSpace behaviour on Option+Tab.
      "workspaceBackAndForth" = "Option+Tab";
      "focusPrevious" = "Unassigned";

      # AeroSpace's alt-0, paired with the tenth workspace declared above.
      "switchWorkspace.9" = "Option+0";
      "moveToWorkspace.9" = "Option+Shift+0";
    };

    # Owned by the machine rather than this repo: every one of these is keyed by
    # a display UUID or records how the displays are arranged on the desk. The
    # activation script carries whatever the live file holds at these paths over
    # to the regenerated one, so they survive a switch. Set them up once with
    # OmniWM's own Monitors settings.
    preserveSettings = [
      "routing"
      "monitors"
      "monitorBarOverrides"
      "monitorDwindleOverrides"
      "monitorGapOverrides"
      "monitorNiriOverrides"
      "monitorOrientationOverrides"
    ];
  };
}
