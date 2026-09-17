{ lib, ... }:
{
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
    next_tab = "ctrl+p"

    [[keys.command]]
    key = "prefix+l"
    type = "popup"
    command = "lazygit"
    description = "run lazygit"
    width = "80%"
    height = "80%"

    # Herdr Picker plugin — fuzzy-launch spaces / worktrees / commands / agents.
    [[keys.command]]
    key = "ctrl+C"
    type = "plugin_action"
    command = "herdr-picker.launch"
    description = "fuzzy-launch (spaces / worktrees / commands / agents)"
  '';

  # Copy the plugins into stable, writable directories and register them with
  # herdr, idempotently (only links when not already present).
  home.activation.herdrPickerPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pluginDir="$HOME/.config/herdr/plugins-managed/picker"
    mkdir -p "$pluginDir"
    cp -f "${./plugins/picker/herdr-plugin.toml}" "$pluginDir/herdr-plugin.toml"
    cp -f "${./plugins/picker/launcher.sh}" "$pluginDir/launcher.sh"
    chmod +x "$pluginDir/launcher.sh"

    # Repo-managed picker settings -> plugin config dir (real, editable file;
    # a store symlink would be read-only). herdr seeds nothing if this exists.
    pickerCfg="$HOME/.config/herdr/plugins/config/herdr-picker"
    mkdir -p "$pickerCfg"
    cp -f "${./plugins/picker/config.toml}" "$pickerCfg/config.toml"

    herdrBin="$(command -v herdr 2>/dev/null || true)"
    [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
    if [ -x "$herdrBin" ]; then
      if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-picker"; then
        "$herdrBin" plugin link "$pluginDir" >/dev/null 2>&1 || true
      fi
    fi
  '';

  # herdr-automations — a .sh herdr plugin: cron-scheduled automations.
  # Each automation names a cron schedule, workspace, agent, and command;
  # a daemon (spawned by the plugin's [[startup]] hook) fires due ones as
  # visible herdr workspaces. Same stable-dir + `herdr plugin link` pattern
  # as the picker above.
  #
  # Automation TOML files are user data, not repo-managed: activation seeds
  # the example file only when automations/ does not exist yet, and never
  # overwrites afterwards. The daemon picks up edits within a minute.
  home.activation.herdrAutomationsPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    autoDir="$HOME/.config/herdr/plugins-managed/automations"
    mkdir -p "$autoDir"
    cp -f "${./plugins/automations/herdr-plugin.toml}" "$autoDir/herdr-plugin.toml"
    cp -f "${./plugins/automations/automations.sh}" "$autoDir/automations.sh"
    chmod +x "$autoDir/automations.sh"

    autoCfg="$HOME/.config/herdr/plugins/config/herdr-automations/automations"
    if [ ! -d "$autoCfg" ] || [ -z "$(ls -A "$autoCfg" 2>/dev/null)" ]; then
      mkdir -p "$autoCfg"
      cp -f "${./plugins/automations/example-cron.toml}" "$autoCfg/example-cron.toml"
    fi

    herdrBin="$(command -v herdr 2>/dev/null || true)"
    [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
    if [ -x "$herdrBin" ]; then
      if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-automations"; then
        "$herdrBin" plugin link "$autoDir" >/dev/null 2>&1 || true
      fi
    fi
  '';
}
