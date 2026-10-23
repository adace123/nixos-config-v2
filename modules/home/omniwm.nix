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
    # OmniWM's own floors, minus the entries for apps this machine does not have
    # — Commander One, Outlook, Firefox, Arc, iTerm2, kitty, Alacritty, Zed, VS
    # Code and Cursor. A rule for an absent app only fires if it is installed,
    # so leaving them was dead weight rather than a bug; they are gone so the
    # list reads as what this desk actually runs. Dia is the addition upstream
    # does not carry.
    "com.openai.codex" = floor 800.0 600.0;
    "com.apple.Safari" = floor 574.0 220.0;
    "app.zen-browser.zen" = floor 500.0 495.0;
    "com.apple.MobileSMS" = floor 660.0 320.0;

    # Browsers — workspace 1.
    "com.google.Chrome" = (floor 500.0 375.0) // {
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
      displayName = "📺";
      monitorAssignment.type = "tertiary";
    }
    { }
    { }
    { }
    { }
  ];

  # The workspace the TV owns, read back out of `workspaceSpecs` by the role it is
  # assigned — so moving the 📺 entry is enough to move this with it. It is what
  # `appWorkspacesHandler` moves onto a TV that is connected but showing nothing.
  tvWorkspace = toString (
    lib.lists.findFirstIndex (
      spec: (spec.monitorAssignment.type or null) == "tertiary"
    ) (throw "omniwm: no workspace in `workspaceSpecs` is assigned to the tertiary role") workspaceSpecs
    + 1
  );

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
      # and a child that leaves the pipe unread upsets the writer. Keep the
      # envelope rather than discarding it, because its `channel` is what tells
      # the lid handler at the bottom that a display actually came or went,
      # rather than a window merely moving.
      event=$(cat) || event=""

      # A display that goes away — lid closed, monitor unplugged — takes its
      # workspaces with it. The windows survive, but they have no display left
      # to be drawn on, which reads as "the app is running and clicking its Dock
      # icon does nothing". This pulls back the ones whose frames ended up off
      # every remaining display. OmniWM answers `no_change` when there are none,
      # so running it on every event costs one no-op IPC call and never moves a
      # window the user parked somewhere on purpose.
      omniwmctl command rescue-offscreen-windows >/dev/null 2>&1 || true

      displays=$(omniwmctl query displays --fields id,name,active-workspace --format json) || exit 0

      dia_bundle="${diaBundleId}"
      dia_home="${diaWorkspace}"
      ghostty_bundle="${ghosttyBundleId}"
      ghostty_home="${ghosttyWorkspace}"
      tv_home="${tvWorkspace}"

      # Name of the workspace a displays payload says the TV is showing — empty
      # when no display is named like a TV, and empty when the TV is showing
      # nothing at all.
      tv_showing() {
        printf '%s' "$1" | jq -r '
          [.result.payload.displays[]? | select((.name // "") | test("tv"; "i"))]
          | first // {}
          | .activeWorkspace.rawName // ""'
      }

      # The TV is whichever connected display's name mentions it. Dia belongs on
      # the workspace that display is showing — a workspace belongs to one
      # display at a time, so naming that workspace is the same as naming the TV
      # — and on the browsers' workspace when there is no such display.
      tv_connected=$(printf '%s' "$displays" | jq -r '
        [.result.payload.displays[]? | select((.name // "") | test("tv"; "i"))]
        | length > 0')
      tv_workspace=$(tv_showing "$displays")

      # A TV that is connected and showing nothing gets the TV workspace put on
      # it. Roles are positional, so the `tertiary` assignment the specs give
      # that workspace only reaches the TV when three displays are up — the
      # built-in, the monitor and the TV. With the monitor away or the lid closed
      # the TV sorts second and takes `secondary`, `tertiary` has no display at
      # all, and the TV workspace falls back to the built-in: the TV is left
      # blank, `tv_workspace` above comes back empty, and the reconcile below has
      # nothing to aim Dia at, so it parks the browser on the browsers'
      # workspace instead. Naming the workspace outright is the only placement
      # that does not depend on how many displays happen to be connected.
      #
      # `move-to-monitor` walks the routing grid rather than the display frames,
      # so which direction reaches the TV depends on how the desk is arranged in
      # OmniWM's own Monitors settings — a grid preserved from the live file
      # rather than committed here. Try each until one lands: a direction with no
      # display behind it answers `not_found` and moves nothing, and the loop
      # stops as soon as the TV reports a workspace, so this costs one IPC call
      # in the common case and nothing at all once the TV has its workspace.
      # `--force` overrides the configured assignment for this placement only;
      # the settings file keeps `tertiary`, so the next display change starts the
      # loop over rather than leaving a stale override behind.
      if [ "$tv_connected" = true ] && [ -z "$tv_workspace" ]; then
        for direction in up right down left; do
          omniwmctl workspace move-to-monitor "$tv_home" "$direction" --force >/dev/null 2>&1 || true
          tv_workspace=$(tv_showing "$(omniwmctl query displays --fields id,name,active-workspace --format json)")
          if [ -n "$tv_workspace" ]; then
            break
          fi
        done
      fi

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

      # Closing the lid gets the browser onto the monitor, but the monitor comes
      # back up on whichever workspace it was last showing — usually the
      # terminals — so the browser that just migrated is on a workspace nobody
      # is looking at. Put it on the browsers' workspace, once per display
      # change and only in clamshell: keying on the event channel rather than
      # the lid alone is what keeps this out of the way, because a window event
      # cannot re-trigger it and switching workspace afterwards stays put.
      #
      # `/usr/sbin/ioreg` is written out in full: `writeShellApplication` puts
      # only `runtimeInputs` on PATH, and ioreg is an Apple binary, not a
      # package.
      case "$event" in
        *display-changed*)
          if /usr/sbin/ioreg -r -k AppleClamshellState -d 4 2>/dev/null |
            grep -q '"AppleClamshellState" = Yes'; then
            omniwmctl workspace focus-name "$dia_home" >/dev/null 2>&1 || true
          fi
          ;;
      esac
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

    # AeroSpace's gap geometry: 8pt between windows, 8pt at every screen edge —
    # except the top. OmniWM ships 16pt inner gaps and no outer gaps.
    #
    # `outer.top` is 10 rather than 8 because the workspace bar is reserved but
    # the 8pt outer plus 8pt inner gap left only 16pt of clear space under a
    # 24pt bar, which reads as the window touching it. 10pt gives 18pt under the
    # bar; the other three edges stay at AeroSpace's 8.
    #
    # `fullscreenUsesOuterGaps` is on for the same reason: a fullscreen window
    # otherwise fills the display right up to the bar (the bar stays reserved,
    # so it lands 24pt down with nothing between the two). With it, fullscreen
    # takes the same outer gaps as a tiled window and leaves the same strip.
    settings.gaps = {
      size = 8.0;
      fullscreenUsesOuterGaps = true;
      outer = {
        left = 8.0;
        right = 8.0;
        top = 10.0;
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

      # `position` is `overlappingMenuBar`, so the bar floats over the top of the
      # display instead of taking a row of its own. Without reserving layout
      # space the tiled work area still runs to the top edge and the top of every
      # window ends up behind the bar; reserving it pushes the work area down by
      # the bar's height.
      #
      # A real macOS fullscreen Space is composited above everything, so a bar
      # that stays put is simply covered. Native fullscreen is the one case the
      # reservation cannot help, so the bar steps aside instead.
      hideInNativeFullscreen = true;
      reserveLayoutSpace = true;
    };

    # `singleWindowFit` is left at OmniWM's default, "fill": a lone window keeps
    # its 8pt side and bottom gaps anyway, because `fullscreenUsesOuterGaps` above
    # lands a fill window on the working frame those gaps were subtracted from.
    # One window on a workspace looks the same as several, in both layouts.
    #
    # Do not give it a value OmniWM does not define — the only ones it decodes are
    # "fill", "container_primary_span" (Niri only) and an explicit "WxH" size.
    # A commit here once set "preserve", which no OmniWM release defines, and a
    # single undecodable value makes OmniWM reject the *whole* settings file and
    # run on its packaged defaults: the bar dropped below the notch on a second
    # row, the gaps and hotkeys reverted, and `ipcEnabled` went back to false,
    # which is what left `omniwmctl` unable to reach the app. Nothing in the app
    # says so; the rejection is only in the unified log:
    #
    #   log show --predicate 'subsystem == "com.barut.OmniWM"' --last 10m

    # AeroSpace had no drop-down terminal, and OmniWM's binds Option+` by
    # default. Flip this to true to get its Ghostty-backed quake terminal.
    settings.quakeTerminal.enabled = false;

    # Ten workspaces named 1–10, assigned to the main display except 6, which is
    # the TV workspace and takes the tertiary role — the same shape OmniWM
    # ships, plus the tenth workspace AeroSpace's alt-0 bound. Roles are used
    # rather than display UUIDs so swapping monitors needs no change here.
    # `workspaceSpecs` also tells the TV watcher which workspace the TV owns.
    #
    # One TV workspace is enough: the watcher sends every Dia window to whatever
    # workspace the TV is showing, and back to the browsers' workspace when it
    # goes. `tertiary` is what lands it on the TV — the TV is deliberately left
    # out of the Monitor Roles ranking, so it sorts after the built-in display
    # and the monitor and takes the third role. With no TV connected that role
    # has no display and the workspace falls back to the monitor, which costs
    # nothing for an empty workspace but does mean ranking the TV would break
    # this: a ranked TV becomes secondary and the monitor becomes tertiary.
    #
    # The role only holds up on the full three-display desk. With the monitor
    # away the TV sorts second and takes `secondary`, `tertiary` is left without
    # a display, and this workspace falls back to the built-in — leaving the TV
    # blank. That is why the watcher does not simply trust the role: it moves
    # the workspace onto a TV that is showing nothing before reconciling.
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

      # OmniWM ships this one unassigned. It returns windows stranded on a
      # display that has gone away to the connected ones: the recovery key for
      # anything the `rescue-offscreen-windows` call in the watcher above could
      # not reach, and for a display that vanished without OmniWM noticing.
      # `Control+Option+R` is `resetWindowSecondarySpan`, so this takes the Shift
      # chord; it is Control-based, which keeps it firing while Secure Input has
      # the Option chords paused.
      "rescueOffscreenWindows" = "Control+Option+Shift+R";
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
