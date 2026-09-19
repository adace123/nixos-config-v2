{
  lib,
  inputs,
  pkgs,
  ...
}:
let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  # The kanban board plugin (plugins/kanban): a Textual TUI packaged with
  # python3.withPackages [ textual ] plus the manifest/config the activation
  # script below deploys. See kanban-package.nix.
  kanban = import ./kanban-package.nix { inherit pkgs; };
in
{
  home.packages = [
    llmAgents.herdr
    # Standalone entry point for the board: `herdr-kanban --snapshot`,
    # `herdr-kanban --selftest`, or just `herdr-kanban` outside herdr.
    kanban.cli
  ];
  # herdr plugins (both .sh plugins, deployed via the activation scripts
  # below): herdr-picker (fuzzy launcher) and herdr-automations
  # (cron-scheduled agent runs).
  #
  # Deployment: because `herdr plugin link` canonicalises the linked path (a
  # store symlink would go stale on every rebuild), the activation script below
  # copies the two plugin files into a stable, real directory
  # (~/.config/herdr/plugins-managed/picker) and links that path once.
  xdg.configFile."herdr/config.toml".text = ''
    onboarding = false

    [theme]
    name = "catppuccin"
    auto_switch = false

    [ui] 
    toast.delivery = "system"

    [keys]
    focus_pane_left = "ctrl+H"
    focus_pane_right = "ctrl+L"
    focus_pane_up = "ctrl+K"
    focus_pane_down = "ctrl+J"
    split_vertical = "ctrl+V"
    goto = "ctrl+G"
    workspace_picker = "ctrl+P"
    navigate_workspace_up = "k"
    navigate_workspace_down = "j"
    previous_workspace = "ctrl+["
    next_workspace = "ctrl+]"
    previous_agent = "ctrl+{"
    next_agent = "ctrl+}"
    # Prefix-free tab switching. Not ctrl+tab/ctrl+shift+tab: Ghostty's
    # built-in `ctrl+tab=next_tab` keybind consumes those before herdr sees
    # them. Both chords below are unbound in Ghostty, and herdr pushes the
    # Kitty keyboard protocol to the outer terminal, so they arrive as
    # CSI 44;5u / 46;5u rather than being swallowed.
    previous_tab = "ctrl+,"
    next_tab = "ctrl+."

    [[keys.command]]
    key = "prefix+l"
    type = "popup"
    command = "lazygit"
    description = "run lazygit"
    width = "80%"
    height = "80%"

    # herdr-kanban plugin — the board overlay (plugins/kanban).
    [[keys.command]]
    key = "prefix+k"
    type = "plugin_action"
    command = "herdr-kanban.open"
    description = "kanban board"

    # ...and quick capture into it: a centred popup with the add form, seeded
    # from the workspace you are in. Enter saves and closes the popup.
    #
    # A direct terminal-mode chord (no prefix), because capture should be one
    # keystroke. Some terminals collapse ctrl+shift+<letter> into ctrl+<letter>;
    # if this one does nothing, use "prefix+shift+k" instead.
    [[keys.command]]
    key = "ctrl+A"
    type = "plugin_action"
    command = "herdr-kanban.quick-add"
    description = "kanban: capture a task"
  '';

  # Copy the plugins into stable, writable directories and register them with
  # herdr, idempotently (only links when not already present).
  # home.activation.herdrPickerPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   pluginDir="$HOME/.config/herdr/plugins-managed/picker"
  #   mkdir -p "$pluginDir"
  #   cp -f "${./plugins/picker/herdr-plugin.toml}" "$pluginDir/herdr-plugin.toml"
  #   cp -f "${./plugins/picker/launcher.sh}" "$pluginDir/launcher.sh"
  #   chmod +x "$pluginDir/launcher.sh"
  #
  #   # Repo-managed picker settings -> plugin config dir (real, editable file;
  #   # a store symlink would be read-only). herdr seeds nothing if this exists.
  #   pickerCfg="$HOME/.config/herdr/plugins/config/herdr-picker"
  #   mkdir -p "$pickerCfg"
  #   cp -f "${./plugins/picker/config.toml}" "$pickerCfg/config.toml"
  #
  #   herdrBin="$(command -v herdr 2>/dev/null || true)"
  #   [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
  #   if [ -x "$herdrBin" ]; then
  #     if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-picker"; then
  #       "$herdrBin" plugin link "$pluginDir" >/dev/null 2>&1 || true
  #     fi
  #   fi
  # '';

  # herdr-automations — a .sh herdr plugin: cron-scheduled automations.
  # Each automation names a cron schedule, workspace, agent, and command;
  # a daemon (spawned by the plugin's [[startup]] hook) fires due ones as
  # visible herdr workspaces. Same stable-dir + `herdr plugin link` pattern
  # as the picker above.
  #
  # Automation TOML files are user data, not repo-managed: activation seeds
  # the example file only when automations/ does not exist yet, and never
  # overwrites afterwards. The daemon picks up edits within a minute.
  # home.activation.herdrAutomationsPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  #   autoDir="$HOME/.config/herdr/plugins-managed/automations"
  #   mkdir -p "$autoDir"
  #   cp -f "${./plugins/automations/herdr-plugin.toml}" "$autoDir/herdr-plugin.toml"
  #   cp -f "${./plugins/automations/automations.sh}" "$autoDir/automations.sh"
  #   chmod +x "$autoDir/automations.sh"
  #
  #   autoCfg="$HOME/.config/herdr/plugins/config/herdr-automations/automations"
  #   if [ ! -d "$autoCfg" ] || [ -z "$(ls -A "$autoCfg" 2>/dev/null)" ]; then
  #     mkdir -p "$autoCfg"
  #     cp -f "${./plugins/automations/example-cron.toml}" "$autoCfg/example-cron.toml"
  #   fi
  #
  #   herdrBin="$(command -v herdr 2>/dev/null || true)"
  #   [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
  #   if [ -x "$herdrBin" ]; then
  #     if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-automations"; then
  #       "$herdrBin" plugin link "$autoDir" >/dev/null 2>&1 || true
  #     fi
  #   fi
  # '';

  # herdr-kanban — a kanban board plugin (plugins/kanban/): tasks carry the
  # workspace they belong to and the agent that should do them; dispatching a
  # card opens a tab in that workspace, starts the agent, and hands it the task.
  # Same stable-dir + `herdr plugin link` pattern as the plugins above: the
  # manifest and launcher are copied into a real, writable directory because
  # `herdr plugin link` canonicalises the linked path, so a store symlink would
  # go stale on the next rebuild. The Python app stays in the store; the copied
  # launcher bakes in the store paths for the app and its interpreter.
  home.activation.herdrKanbanPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    kanbanDir="$HOME/.config/herdr/plugins-managed/kanban"
    mkdir -p "$kanbanDir"
    cp -f "${kanban.manifest}" "$kanbanDir/herdr-plugin.toml"
    cp -f "${kanban.launcher}" "$kanbanDir/launcher.sh"
    chmod +x "$kanbanDir/launcher.sh"

    # Repo-managed defaults (columns, placement, icon mode, sync cadence) go to
    # the plugin config dir on every activation: config.toml here is the source
    # of truth, exactly like the picker's. The board stores its tasks in
    # ~/.local/state/herdr/plugins/herdr-kanban/board.json instead, so a switch
    # never touches them.
    kanbanCfg="$HOME/.config/herdr/plugins/config/herdr-kanban"
    mkdir -p "$kanbanCfg"
    cp -f "${kanban.config}" "$kanbanCfg/config.toml"

    herdrBin="$(command -v herdr 2>/dev/null || true)"
    [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
    if [ -x "$herdrBin" ]; then
      if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-kanban"; then
        "$herdrBin" plugin link "$kanbanDir" >/dev/null 2>&1 || true
      fi
      # Apply the prefix+k binding written above to the running server.
      "$herdrBin" server reload-config >/dev/null 2>&1 || true
    fi
  '';
}
