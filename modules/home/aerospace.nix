_:

{
  # AeroSpace window manager configuration
  # AeroSpace is a tiling window manager for macOS inspired by i3

  home.file.".aerospace.toml".text = ''
    # AeroSpace Configuration
    # Documentation: https://github.com/nikitabobko/AeroSpace

    # Start AeroSpace at login
    start-at-login = true

    # Normalizations. See: https://nikitabobko.github.io/AeroSpace/guide#normalization
    enable-normalization-flatten-containers = true
    enable-normalization-opposite-orientation-for-nested-containers = true

    # See: https://nikitabobko.github.io/AeroSpace/guide#layouts
    # The 'accordion-padding' specifies the size of accordion padding
    # You can set 0 to disable the padding feature
    accordion-padding = 30

    # Possible values: tiles|accordion
    default-root-container-layout = 'tiles'

    # Possible values: horizontal|vertical|auto
    # 'auto' means: wide monitor (anything wider than high) gets horizontal orientation,
    #               tall monitor (anything higher than wide) gets vertical orientation
    default-root-container-orientation = 'auto'

    # Mouse follows focus when focused monitor changes
    on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

    # Gaps between windows (inner gaps)
    gaps.inner.horizontal = 8
    gaps.inner.vertical = 8

    # Gaps between windows and screen edges (outer gaps)
    gaps.outer.left = 8
    gaps.outer.bottom = 8
    gaps.outer.top = 8
    gaps.outer.right = 8

    # Key Mappings
    # All possible keys: https://nikitabobko.github.io/AeroSpace/guide#key-mapping

    # Main modifier key (alt/option key)
    [mode.main.binding]

    # See: https://nikitabobko.github.io/AeroSpace/commands#layout
    alt-slash = 'layout tiles horizontal vertical'
    alt-comma = 'layout accordion horizontal vertical'

    # See: https://nikitabobko.github.io/AeroSpace/commands#focus
    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'

    # See: https://nikitabobko.github.io/AeroSpace/commands#move
    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'

    # See: https://nikitabobko.github.io/AeroSpace/commands#resize
    alt-shift-minus = 'resize smart -50'
    alt-shift-equal = 'resize smart +50'

    # See: https://nikitabobko.github.io/AeroSpace/commands#workspace
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'
    alt-0 = 'workspace 10'

    # See: https://nikitabobko.github.io/AeroSpace/commands#move-node-to-workspace
    alt-shift-1 = 'move-node-to-workspace 1'
    alt-shift-2 = 'move-node-to-workspace 2'
    alt-shift-3 = 'move-node-to-workspace 3'
    alt-shift-4 = 'move-node-to-workspace 4'
    alt-shift-5 = 'move-node-to-workspace 5'
    alt-shift-6 = 'move-node-to-workspace 6'
    alt-shift-7 = 'move-node-to-workspace 7'
    alt-shift-8 = 'move-node-to-workspace 8'
    alt-shift-9 = 'move-node-to-workspace 9'
    alt-shift-0 = 'move-node-to-workspace 10'

    # See: https://nikitabobko.github.io/AeroSpace/commands#workspace-back-and-forth
    alt-tab = 'workspace-back-and-forth'

    # See: https://nikitabobko.github.io/AeroSpace/commands#move-workspace-to-monitor
    alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

    # See: https://nikitabobko.github.io/AeroSpace/commands#mode
    alt-shift-semicolon = 'mode service'

    # 'service' binding mode declaration.
    # See: https://nikitabobko.github.io/AeroSpace/guide#binding-modes
    [mode.service.binding]
    esc = ['reload-config', 'mode main']
    r = ['flatten-workspace-tree', 'mode main'] # reset layout
    f = ['layout floating tiling', 'mode main'] # Toggle between floating and tiling layout
    backspace = ['close-all-windows-but-current', 'mode main']

    alt-shift-h = ['join-with left', 'mode main']
    alt-shift-j = ['join-with down', 'mode main']
    alt-shift-k = ['join-with up', 'mode main']
    alt-shift-l = ['join-with right', 'mode main']

    # Workspace to monitor assignment
    [[workspace-to-monitor-force-assignment]]
    workspace = 1
    monitor = ['main']

    [[workspace-to-monitor-force-assignment]]
    workspace = [2, 3, 4, 5]
    monitor = ['main', 'secondary']

    # Application-specific rules
    # See: https://nikitabobko.github.io/AeroSpace/guide#assign-workspaces-to-monitors

    # Browsers on workspace 1
    [[on-window-detected]]
    if.app-id = 'com.google.Chrome'
    run = 'move-node-to-workspace 1'

    [[on-window-detected]]
    if.app-id = 'org.mozilla.firefox'
    run = 'move-node-to-workspace 1'

    [[on-window-detected]]
    if.app-id = 'company.thebrowser.Browser'
    run = 'move-node-to-workspace 1'

    # Terminal on workspace 2
    [[on-window-detected]]
    if.app-id = 'com.apple.Terminal'
    run = 'move-node-to-workspace 2'

    [[on-window-detected]]
    if.app-id = 'com.googlecode.iterm2'
    run = 'move-node-to-workspace 2'

    [[on-window-detected]]
    if.app-id = 'net.kovidgoyal.kitty'
    run = 'move-node-to-workspace 2'

    [[on-window-detected]]
    if.app-id = 'io.alacritty'
    run = 'move-node-to-workspace 2'

    [[on-window-detected]]
    if.app-id = 'com.mitchellh.ghostty'
    run = 'move-node-to-workspace 2'

    # Code editors on workspace 3
    [[on-window-detected]]
    if.app-id = 'com.microsoft.VSCode'
    run = 'move-node-to-workspace 3'

    [[on-window-detected]]
    if.app-id = 'com.todesktop.230313mzl4w4u92'
    run = 'move-node-to-workspace 3'

    [[on-window-detected]]
    if.app-id = 'dev.zed.Zed'
    run = 'move-node-to-workspace 3'

    # Communication on workspace 4
    [[on-window-detected]]
    if.app-id = 'com.tinyspeck.slackmacgap'
    run = 'move-node-to-workspace 4'

    [[on-window-detected]]
    if.app-id = 'com.hnc.Discord'
    run = 'move-node-to-workspace 4'

    [[on-window-detected]]
    if.app-id = 'us.zoom.xos'
    run = 'move-node-to-workspace 4'

    # Music/Media on workspace 5
    [[on-window-detected]]
    if.app-id = 'com.spotify.client'
    run = 'move-node-to-workspace 5'

    # Floating windows (don't tile these)
    [[on-window-detected]]
    if.app-id = 'com.apple.systempreferences'
    run = 'layout floating'

    [[on-window-detected]]
    if.app-id = 'com.apple.ActivityMonitor'
    run = 'layout floating'

    [[on-window-detected]]
    if.app-id = 'com.apple.finder'
    run = 'layout floating'

    [[on-window-detected]]
    if.app-id = 'com.1password.1password'
    run = 'layout floating'
  '';

  # Shell aliases for AeroSpace
  programs.zsh.shellAliases = {
    # AeroSpace control
    aero = "aerospace";
    aero-reload = "aerospace reload-config";
    aero-list = "aerospace list-windows --all";
    aero-workspaces = "aerospace list-workspaces --all";
  };
}
