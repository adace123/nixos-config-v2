{
  config,
  inputs,
  lib,
  pkgs,
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

  # The package the module below installs. The TV watcher runs its `omniwmctl`.
  omniwm = config.programs.omniwm.package;

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
    # Upstream defaults, reproduced verbatim — except Dia, which the browser group
    # below owns.
    "com.openai.codex" = floor 800.0 600.0;
    "com.eltima.cmd1.pro.mas" = floor 950.0 550.0;
    "com.apple.Safari" = floor 574.0 220.0;
    "app.zen-browser.zen" = floor 500.0 495.0;
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
    # Dia keeps its floor and joins the group. Its workspace is also the one the
    # TV overrides, so `diaWorkspace` below reads it back out of here.
    "company.thebrowser.dia" = (floor 500.0 420.0) // {
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

  # The apps whose windows this file keeps on their own workspace even after the
  # first one. OmniWM's `assignToWorkspace` only applies while an app has no
  # tracked windows, so a second window opens on whatever workspace was active;
  # AeroSpace's on-window-detected rules applied to every window, and
  # `appWorkspacesHandler` below is what restores that.
  #
  # Dia is the one the TV argues with: while the TV is connected as a display,
  # every Dia window belongs on the workspace that display is showing, and they
  # go back to the browsers' workspace when it does.
  #
  # OmniWM cannot express the TV half in `settings` either — an app rule assigns
  # a *workspace*, and which display that workspace lands on is decided by its
  # home monitor, so a rule would pin Dia to one fixed TV workspace even with
  # the TV unplugged.
  diaBundleId = "company.thebrowser.dia";
  ghosttyBundleId = "com.mitchellh.ghostty";
  diaWorkspace = appRules."${diaBundleId}".assignToWorkspace;
  ghosttyWorkspace = appRules."${ghosttyBundleId}".assignToWorkspace;

  # Workspace specs by position — `omniwmLib.workspaces` takes `name` from the
  # position, which is what the `assignToWorkspace` rules above address.
  workspaceSpecs = [
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

  # Runs once per OmniWM event, from the launchd agent further down. Everything
  # it wants to know is read live over IPC rather than out of the event payload,
  # so it finds the state it is looking for and does nothing when the event was
  # about a window or a display it has no opinion on.
  #
  # `omniwmctl` needs `general.ipcEnabled` (set below). OmniWM's IPC socket is
  # same-user only — 0600 in ~/Library/Application Support, plus a token file —
  # which is the trust boundary its documentation states.
  appWorkspacesHandler = pkgs.writeShellApplication {
    name = "omniwm-app-workspaces";
    runtimeInputs = [
      omniwm
      pkgs.jq
    ];
    text = ''
      # `omniwmctl watch` writes one event envelope to this process's stdin and
      # waits for it to exit. Drain it: the reconcile below wants live state,
      # and a child that leaves the pipe unread upsets the writer.
      cat >/dev/null || true

      displays=$(omniwmctl query displays --fields id,name,active-workspace --format json) || exit 0

      # The TV is whichever connected display's name mentions it. Dia belongs on
      # the workspace that display is showing — a workspace belongs to one
      # display at a time, so naming that workspace is the same as naming the TV
      # — and on the browsers' workspace when there is no such display.
      tv_workspace=$(printf '%s' "$displays" | jq -r '
        [.result.payload.displays[]? | select((.name // "") | test("tv"; "i"))]
        | first // {}
        | .activeWorkspace.rawName // ""')

      dia_bundle="${diaBundleId}"
      dia_home="${diaWorkspace}"
      ghostty_bundle="${ghosttyBundleId}"
      ghostty_home="${ghosttyWorkspace}"

      windows=$(omniwmctl query windows --fields id,app,workspace --format json) || exit 0

      # One line per window that is in the wrong place: its id, and the workspace
      # it belongs on. A window that is already home costs nothing but the
      # query, and a move that changes nothing reports `no_change`.
      while IFS=$'\t' read -r window target; do
        if [ -z "$window" ]; then continue; fi
        omniwmctl window move-to-workspace "$window" "$target" >/dev/null 2>&1 || true
      done < <(printf '%s' "$windows" | jq -r \
        --arg dia "$dia_bundle" --arg dia_home "$dia_home" \
        --arg tv_workspace "$tv_workspace" \
        --arg ghostty "$ghostty_bundle" --arg ghostty_home "$ghostty_home" '
        .result.payload.windows[]?
        | select(.app.bundleId? == $dia or .app.bundleId? == $ghostty)
        | (if .app.bundleId == $dia and $tv_workspace != ""
           then $tv_workspace
           elif .app.bundleId == $dia
           then $dia_home
           else $ghostty_home
           end) as $target
        | select((.workspace.rawName // "") != $target)
        | [.id, $target] | @tsv')
    '';
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

      # `omniwmctl` talks to OmniWM over a same-user Unix socket, and the Dia/TV
      # watcher below is its only caller here. Off by default.
      ipcEnabled = true;
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

    # The bar rides in the macOS menu-bar strip, split around the notch with the
    # active workspace docked on its left. The packaged default,
    # "moveBelowMenuBar", dodges the notch by dropping the island onto a second
    # row instead, which is what put two bars under the notch on the built-in
    # display. macOS's own bar is auto-hidden (`_HIHideMenuBar` in
    # modules/darwin/default.nix), so this is the only one up there.
    settings.workspaceBar = {
      notchMode = "splitActiveLeft";
    };

    # AeroSpace had no drop-down terminal, and OmniWM's binds Option+` by
    # default. Flip this to true to get its Ghostty-backed quake terminal.
    settings.quakeTerminal.enabled = false;

    # Ten workspaces named 1–10, assigned to the main display except 6 and 7 on
    # the secondary one — the same shape OmniWM ships, plus the tenth workspace
    # AeroSpace's alt-0 bound. Roles are used rather than display UUIDs so
    # swapping monitors needs no change here. `workspaceSpecs` also tells the
    # TV watcher which workspaces the TV owns.
    settings.workspaces = omniwmLib.workspaces workspaceSpecs;

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

      # OmniWM ships the workspace layout toggle on Option+Shift+L, the chord
      # move.right just took. When two actions claim one chord OmniWM drops
      # *both* from its registration, so neither fires; the toggle gives the key
      # up, the way focusPrevious gives up Option+Tab below.
      "toggleWorkspaceLayout" = "Unassigned";

      # AeroSpace's alt-tab switched to the previous workspace. OmniWM gives
      # that action Control+Option+Tab and binds Option+Tab to the previous
      # *window*; since one shortcut can only drive one action, focusPrevious
      # gives up its default to keep the AeroSpace behaviour on Option+Tab.
      "workspaceBackAndForth" = "Option+Tab";
      "focusPrevious" = "Unassigned";

      # AeroSpace's alt-0, paired with the tenth workspace declared above.
      "switchWorkspace.9" = "Option+0";
      "moveToWorkspace.9" = "Option+Shift+0";

      # Step through the monitor's workspaces in order, where OmniWM leaves both
      # unassigned and AeroSpace had them on the same keys.
      #
      # Both are Option chords, so OmniWM pauses them while macOS Secure Input
      # is active — a password field, 1Password, Ghostty's Secure Keyboard
      # Entry. It pauses every shortcut that would type a character unless the
      # chord uses Control or Command, and these would type “ and ”. Bind
      # Control+Left Bracket / Control+Right Bracket instead if that bites.
      "switchWorkspace.previous" = "Option+Left Bracket";
      "switchWorkspace.next" = "Option+Right Bracket";

      # Closing a window, which OmniWM ships unassigned. It is an Option chord
      # like the two above, so the Secure Input caveat applies here too.
      "closeFocusedWindow" = "Option+q";

      # The command palette, which OmniWM ships on Control+Option+Space. Also an
      # Option chord that types a character — Option+S is ß — so it pauses under
      # Secure Input with the rest.
      #
      # It opens on whatever mode was last used, and Windows is only the default
      # of a fresh state: browsed apps once and Applications keeps coming back.
      # 0.7.6 has no key that pins the opening mode. When a release carries the
      # per-mode actions, binding `openCommandPalette.windows` instead opens
      # straight into the window search every time.
      "openCommandPalette" = "Option+S";
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

  # The reconcile runs on both directions of the TV: `display-changed` fires as
  # the TV is adopted or dropped, `windows-changed` catches a Dia or Ghostty
  # window that opens (or lands) somewhere else. The initial snapshots (no
  # `--no-send-initial`) reconcile once at login, and `--reconnect` rides out an
  # OmniWM restart. KeepAlive covers the window before OmniWM's own agent has its
  # IPC server up; the launchd module wraps ProgramArguments in
  # `wait4path /nix/store`, so this does not race the store mount either.
  launchd.agents.omniwm-app-workspaces = {
    enable = config.programs.omniwm.enable;

    config = {
      ProgramArguments = [
        "${omniwm}/bin/omniwmctl"
        "watch"
        "display-changed,windows-changed"
        "--reconnect"
        "--exec"
        "${appWorkspacesHandler}/bin/omniwm-app-workspaces"
      ];

      # `omniwmctl` reads the IPC token from `~/Library/Application Support`,
      # and a launchd agent starts with none of the shell's environment.
      EnvironmentVariables.HOME = config.home.homeDirectory;

      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/omniwm-app-workspaces.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/omniwm-app-workspaces.err.log";
    };
  };
}
