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

  # The package the module below installs. The watchers below run its
  # `omniwmctl`, so they always match the app's IPC protocol.
  #
  # OmniWM 0.8.0 (OmniShell, the editable bar the widget below lives in) is
  # pinned here rather than waited for in `inputs.omniwm`: that flake still
  # packages 0.7.6, and its module merges our settings over a
  # `settings-defaults.toml` generated from the version it packages. Bumping
  # only the binary would pair one version's schema with another's file, so the
  # release is swapped on the input's own packaging and the defaults stay
  # behind until the input catches up.
  #
  # What that costs meanwhile: the module keeps deploying the 0.7.6 schema
  # (version 4), and 0.8.0 migrates it to version 5 on launch — keeping
  # `settings.toml.pre-v5` and adding the new keys — so every activation
  # rewrites the declared values and the next launch migrates again. Values
  # survive; only the migration bookkeeping repeats. Drop the override once
  # `inputs.omniwm` packages 0.8.0.
  omniwm = inputs.omniwm.packages.${pkgs.stdenv.hostPlatform.system}.omniwm.overrideAttrs (_: {
    version = "0.8.0";
    src = pkgs.fetchurl {
      url = "https://github.com/OmniNull/OmniWM/releases/download/v0.8.0/OmniWM-v0.8.0.zip";
      hash = "sha256-b3+z4hHeOoPncrExgAaAyz0g1MY4gRofAhIP0iXwPMc=";
    };
  });

  # Battery levels of the connected Bluetooth accessories, for the battery
  # widget's popout. IOKit keeps them as IOPS "Accessory Source" records — the
  # ones `pmset -g accps` and Control Center read — but only
  # `IOPSCopyPowerSourcesByType` lists them, and that symbol is not in any SDK
  # header. The source has the details.
  bluetoothBattery = pkgs.stdenv.mkDerivation {
    pname = "omniwm-bluetooth-battery";
    version = "0.8.0";
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      $CC -fobjc-arc -framework Foundation -framework IOKit \
        -o bluetooth-battery ${./omniwm/bluetooth-battery.m}
      runHook postBuild
    '';
    installPhase = ''
      install -Dm755 bluetooth-battery $out/bin/bluetooth-battery
    '';
  };

  # OmniWM's shipped minimum sizes for apps with known resize floors. Declaring
  # `appRules` replaces OmniWM's list wholesale instead of extending it, so they
  # are reproduced here; values are from the packaged version's
  # settings-defaults.toml.
  floor = minWidth: minHeight: { inherit minWidth minHeight; };

  # bundleId -> rule body. Floors are OmniWM's own; `assignToWorkspace` and
  # `layout = "float"` mirror the AeroSpace on-window-detected rules this file
  # replaces — browsers on 1, the TV on 2, terminals on 3, chat on 4, media on
  # 5, and the four windows that were floated rather than tiled.
  appRules = {
    # OmniWM's own floors, minus the entries for apps this machine does not have
    # — Commander One, Outlook, Firefox, Arc, iTerm2, kitty, Alacritty, VS
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
    # Dia keeps its floor and joins the group. The TV watcher sends its windows
    # to whatever workspace the TV is showing, so this is only its home when the
    # TV is away; `diaWorkspace` below reads it back out of here.
    "company.thebrowser.dia" = (floor 500.0 420.0) // {
      assignToWorkspace = "1";
    };

    # Terminals — workspace 3. (Workspace 2 is the TV's, see `workspaceSpecs`.)
    "com.mitchellh.ghostty" = (floor 90.0 48.0) // {
      assignToWorkspace = "3";
    };
    "com.apple.Terminal" = {
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
  # position, which is what the `assignToWorkspace` rules above address. The TV
  # takes the second slot so 📺 sits next to the browsers on the working desk.
  workspaceSpecs = [
    { }
    {
      displayName = "📺";
      monitorAssignment.type = "tertiary";
    }
    { }
    { }
    { }
    { }
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

  # Herdr's blocked and finished panes in the OmniShell bar. The watcher follows
  # herdr-core's event stream (`hc events`) and pushes counts and rows as
  # OmniShell runtime values over OmniWM's IPC; the widget renders them. See
  # modules/home/omniwm/herdr-agents/ for the widget and watcher.
  #
  # `jq` and `omniwmctl` come from `runtimeInputs`; `hc` belongs to herdr-core,
  # which the Herdr app installs under ~/.local, so the watcher puts that
  # directory on PATH itself.
  herdrAgentsWatcher = pkgs.writeShellApplication {
    name = "herdr-agents";
    runtimeInputs = [
      omniwm
      pkgs.jq
    ];
    text = builtins.readFile ./omniwm/herdr-agents-watcher.sh;
  };

  # Bluetooth accessory batteries for the battery widget. The watcher polls
  # `bluetooth-battery` (the IOKit helper above) and pushes one runtime value,
  # `bluetooth.batteries`, the same way the Herdr watcher does — widgets cannot
  # launch processes, and values only live as long as OmniWM.
  bluetoothBatteryWatcher = pkgs.writeShellApplication {
    name = "bluetooth-battery-agent";
    runtimeInputs = [
      omniwm
      bluetoothBattery
    ];
    text = builtins.readFile ./omniwm/bluetooth-battery-watcher.sh;
  };

  # Tailscale's login profiles: pushes the current one to the bar and serves a
  # loopback endpoint that switches profiles, because a widget cannot launch a
  # process. `tailscale` comes from nixpkgs and talks to the App Store app's
  # daemon; `omniwmctl` pushes the runtime values the widget reads.
  tailscaleProfiles = pkgs.writeShellApplication {
    name = "tailscale-profiles";
    runtimeInputs = [
      omniwm
      pkgs.python3
      pkgs.tailscale
    ];
    text = ''
      exec python3 ${./omniwm/tailscale-bridge.py}
    '';
  };

  # Appends the widget to the active profile's trailing lane and pins the
  # profile's theme. The shell layout belongs to OmniWM's GUI (it writes
  # ~/.config/omniwm/shell/shell.toml), so this merges into that file instead of
  # deploying one.
  deployShell = pkgs.writers.writeNu "omniwm-deploy-shell" ./omniwm/deploy-shell.nu;

  # A dark-only OmniShell palette for the bar: Catppuccin Mocha surfaces, a
  # translucent smoke fill, a hairline border and pill item backgrounds — the
  # sketchybar look in the reference this theme was drawn from. Bundled themes
  # follow macOS's appearance, so the bar would go light on a light desktop;
  # this one carries the same dark colours in both tables.
  shellTheme = "omniwm-dark";

  # The agent marks, copied into the widget folder at activation (see below)
  # rather than linked: OmniShell resolves an image path with
  # `resolvingSymlinksInPath` and refuses anything that lands outside the widget
  # folder, so a home-manager symlink into the store renders as nothing.
  herdrAgentsAssets = lib.filterAttrs (_: type: type == "regular") (
    builtins.readDir ./omniwm/herdr-agents/assets
  );

  # The Tailscale mark, copied into the widget folder at activation for the same
  # reason as the Herdr marks: `ui.image` rejects a path whose realpath leaves
  # the widget folder, and a home-manager symlink into the store always does.
  tailscaleAssets = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".png" name) (
    builtins.readDir ./omniwm/tailscale/assets
  );
in
{
  imports = [ inputs.omniwm.homeManagerModules.default ];

  programs.omniwm = {
    enable = true;

    # The 0.8.0 override defined above. The input normally supplies this from
    # its own package, but it still packages 0.7.6; see the comment on `omniwm`.
    package = omniwm;

    # Nix owns the binary, so OmniWM's own update check has nothing to do and
    # only reports versions this system will never run. The layout stays Niri —
    # scrolling columns, rather than the tiles/accordion pair AeroSpace had.
    settings.general = {
      updateChecksEnabled = false;
      defaultLayoutType = "niri";

      # `omniwmctl` talks to OmniWM over a same-user Unix socket. Both the
      # Dia/TV watcher and the Herdr agent watcher below are callers. Off by
      # default.
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

      # The split islands sit `notchGap` (8pt, hard-coded in OmniWM) off their
      # side of the notch — but only when the active island is wider than the
      # zone it is allowed to be centred in. At the packaged 180pt the active
      # island was centred inside that zone and so ended ~21pt from the notch
      # while the passive island sat 8pt from it. 60 is the floor the app clamps
      # this to, which puts both sides on the same 8pt gap for any island wider
      # than 60pt.
      notchActiveZoneWidth = 60.0;

      # `position` is `overlappingMenuBar`, so the bar floats over the top of the
      # display instead of taking a row of its own — inside the strip macOS keeps
      # for its (auto-hidden) menu bar, which is what leaves the tiled work area
      # starting at the bottom of that strip. The bar is 24pt in a 32pt strip and
      # bottom-aligned to it, so a window would otherwise start flush against
      # the bar; 1pt of offset lifts the bar off it and leaves one point of
      # background between the two.
      #
      # `reserveLayoutSpace` only matters in `belowMenuBar` mode, where the bar
      # takes a row that has to be carved out of the work area; kept on because
      # the settings below are written for this layout either way.
      #
      # A real macOS fullscreen Space is composited above everything, so a bar
      # that stays put is simply covered. Native fullscreen is the one case the
      # layout cannot help, so the bar steps aside instead.
      hideInNativeFullscreen = true;
      reserveLayoutSpace = true;
      yOffset = 1.0;
    };

    # OmniShell's Dynamic Island. The bar is full width, so the island is the
    # now-playing player: a compact black pill at the top centre — around the
    # notch on the built-in display — whenever a track is playing, expanding
    # into the artwork, scrubber and transport controls on hover or click. The
    # master switch lives here; the root widget, display scope and envelope
    # are merged into the active profile by `deployShell` from
    # `omniwm/island.toml`, and the widget itself is
    # `omniwm/now-playing/init.luau`.
    settings.island.enabled = true;

    # OmniWM ships a 5pt focus ring, which reads heavy against 8pt gaps. Half of
    # it is still a clear outline, and it changes no layout: the ring is drawn in
    # the gap between windows, and each gap is already wider than either width.
    settings.borders.width = 2.5;

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

    # Ten workspaces named 1–10, assigned to the main display except 2, which is
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

      # Hides and restores the OmniShell bar without changing any setting,
      # handing the top strip back to macOS's (auto-hidden) menu bar and Control
      # Center. Unassigned upstream; Control-based, so Secure Input does not
      # pause it.
      "toggleWorkspaceBarVisibility" = "Control+Option+B";
    };

    # The Tailscale widget POSTs to its loopback bridge, and OmniWM holds a
    # widget's first request as "not approved" until a prompt is answered. The
    # approval is declared here so it works on the first click. This owns the
    # whole `shellPermissions.widgets` list — an approval the GUI adds for
    # another widget has to be added here too, or the next activation drops it.
    settings.shellPermissions.widgets = [
      {
        role = "bar";
        name = "tailscale";
        source = "${config.xdg.configHome}/omniwm/shell/widgets/tailscale";
        allowed = [ "127.0.0.1" ];
        denied = [ ];
      }
    ];

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

  # The widget's source. OmniShell reads widgets from these folders and saves
  # placement and options elsewhere (`shell.toml`, the profile), so a read-only
  # store symlink here is never something the app wants to write.
  #
  # Every entry is forced: home-manager only treats a link that resolves into a
  # `home-manager-files` generation as its own, so a copy left in a widget
  # folder by hand — or by an activation that predates the file's move into
  # this list — aborts the whole switch with "would be clobbered". The
  # declaration is authoritative either way; the files are read-only.
  xdg.configFile = lib.mkIf config.programs.omniwm.enable (
    lib.mapAttrs (_: file: file // { force = true; }) {
      "omniwm/shell/widgets/herdr-agents/init.luau".source = ./omniwm/herdr-agents/init.luau;
      "omniwm/shell/widgets/herdr-agents/settings.toml".source = ./omniwm/herdr-agents/settings.toml;

      # Overrides the Default style's `battery-details` widget so its bar icon is
      # purple; OmniShell looks widgets up in the shell folder before the style
      # folder. Its `require("../lib/…")` resolves to the style's library folder,
      # which is why this reads like the style's own copy.
      "omniwm/shell/widgets/battery-details/init.luau".source = ./omniwm/battery-details/init.luau;

      # Likewise the workspaces widget (first five workspaces only) and the
      # weather widget (cyan icon), both forks of the style's copies.
      "omniwm/shell/widgets/workspaces/init.luau".source = ./omniwm/workspaces/init.luau;
      "omniwm/shell/widgets/workspaces/settings.toml".source = ./omniwm/workspaces/settings.toml;
      "omniwm/shell/widgets/weather/init.luau".source = ./omniwm/weather/init.luau;
      "omniwm/shell/widgets/weather/settings.toml".source = ./omniwm/weather/settings.toml;

      # The Tailscale login-profile switcher; its capabilities and permissions are
      # declared in the widget's settings.toml and `shellPermissions` above.
      "omniwm/shell/widgets/tailscale/init.luau".source = ./omniwm/tailscale/init.luau;
      "omniwm/shell/widgets/tailscale/settings.toml".source = ./omniwm/tailscale/settings.toml;

      # The now-playing player. OmniShell resolves this as the island root named
      # in `island.toml`, so it is not in a bar lane; the bundled `media`
      # widget it replaces is removed from the trailing lane at activation.
      "omniwm/shell/widgets/now-playing/init.luau".source = ./omniwm/now-playing/init.luau;
      "omniwm/shell/widgets/now-playing/settings.toml".source = ./omniwm/now-playing/settings.toml;

      # The bar's palette. OmniShell looks a theme up by name in `themes/` under
      # the shell folder, then falls back to the bundled ones, so this is read
      # straight out of the store; a theme file is only ever read, never written.
      "omniwm/shell/themes/${shellTheme}.toml".source = ./omniwm/themes/${shellTheme}.toml;
    }
  );

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

  # OmniShell saves GUI layout into the same file, so this merges into it
  # rather than owning it: everything else stays as written, and a GUI edit that
  # removes the widgets (or picks another theme) is undone at the next
  # activation. It pins the `herdr-agents` lane entry, drops the bundled `media`
  # widget the now-playing player replaces, adds the player as a regular trailing
  # widget for the notched built-in display (the island runs on the others),
  # pins the theme, the bar surface
  # (opacity and height), the weather and Tailscale widgets on the leading lane
  # with the weather location, the island root and envelope, and the per-widget
  # options. The bar keys are repeated here because the style layer pins them
  # ahead of both `settings.workspaceBar` and the theme's `[workspaceBar]`; the
  # profile layer is the only one that wins. The app reads the file on launch
  # and watches it afterwards, so it does not need restarting.
  home.activation.omniwmShellLayout = lib.mkIf config.programs.omniwm.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${deployShell} ''${DRY_RUN:+--dry-run} \
        ${lib.escapeShellArg "${config.xdg.configHome}/omniwm/shell"} herdr-agents \
        ${lib.escapeShellArg shellTheme} --bar-opacity 1.0 --bar-height 28 --item-backgrounds \
        --leading-widgets weather,tailscale --remove-widgets media \
        --trailing-widgets now-playing \
        --weather ${lib.escapeShellArg "${./omniwm/weather.toml}"} \
        --island ${lib.escapeShellArg "${./omniwm/island.toml}"} \
        --widgets ${lib.escapeShellArg "${./omniwm/shell-widgets.toml}"}
    ''
  );

  # Copies the widget's images. OmniShell's image lookup (`ShellImage.resolve`)
  # rejects any path whose realpath leaves the widget folder, which every
  # home-manager symlink into /nix/store does; the widget script and settings are
  # read by name and stay links. Rewriting the real files is what the app's image
  # watcher reloads, so an asset change lands without a restart.
  home.activation.omniwmHerdrAgentsAssets = lib.mkIf config.programs.omniwm.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
      assetDir=${lib.escapeShellArg "${config.xdg.configHome}/omniwm/shell/widgets/herdr-agents/assets"}
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$assetDir"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: _: ''
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$assetDir/${name}"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 ${./omniwm/herdr-agents/assets/${name}} "$assetDir/${name}"
        '') herdrAgentsAssets
      )}
    ''
  );

  # Copies the Tailscale mark beside the widget. Same realpath rule as the Herdr
  # marks above: the file has to be a real copy inside the widget folder.
  home.activation.omniwmTailscaleAssets = lib.mkIf config.programs.omniwm.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
      assetDir=${lib.escapeShellArg "${config.xdg.configHome}/omniwm/shell/widgets/tailscale/assets"}
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$assetDir"
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: _: ''
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -f "$assetDir/${name}"
          $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 644 ${./omniwm/tailscale/assets/${name}} "$assetDir/${name}"
        '') tailscaleAssets
      )}
    ''
  );

  # Herdr agent attention: polls herdr-core's terminal list and pushes the
  # counts the widget above reads. KeepAlive restarts it at login and with the
  # core, and the watcher waits for `hc` and retries IPC while the Herdr app is
  # not up yet.
  launchd.agents.herdr-agents = {
    enable = config.programs.omniwm.enable;

    config = {
      ProgramArguments = [ "${herdrAgentsWatcher}/bin/herdr-agents" ];

      # `hc` lives in ~/.local/bin (herdr-core's own install), and a launchd
      # agent starts with none of the shell's environment.
      EnvironmentVariables = {
        HOME = config.home.homeDirectory;
        PATH = "${config.home.homeDirectory}/.local/bin:/etc/profiles/per-user/${config.home.username}/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };

      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/herdr-agents.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/herdr-agents.err.log";
    };
  };

  # Bluetooth accessory batteries: reads the IOPS accessory power sources and
  # pushes them for the battery widget's popout. KeepAlive restarts it at login
  # and after a crash; a failed IPC push is retried on the next tick.
  launchd.agents.bluetooth-battery = {
    enable = config.programs.omniwm.enable;

    config = {
      ProgramArguments = [ "${bluetoothBatteryWatcher}/bin/bluetooth-battery-agent" ];

      EnvironmentVariables.HOME = config.home.homeDirectory;

      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/bluetooth-battery.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/bluetooth-battery.err.log";
    };
  };

  # Tailscale login profiles: polls the current profile, pushes it to the bar as
  # runtime values, and serves the loopback bridge the widget switches through.
  # KeepAlive restarts it at login and after a crash; the bridge tolerates
  # OmniWM being down by retrying its IPC pushes on the next tick.
  launchd.agents.tailscale-profiles = {
    enable = config.programs.omniwm.enable;

    config = {
      ProgramArguments = [ "${tailscaleProfiles}/bin/tailscale-profiles" ];

      EnvironmentVariables.HOME = config.home.homeDirectory;

      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/tailscale-profiles.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/tailscale-profiles.err.log";
    };
  };
}
