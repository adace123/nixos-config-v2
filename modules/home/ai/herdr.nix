{ lib, ... }:
{
  # herdr-picker — a .sh herdr plugin: a generic fuzzy picker over herdr
  # spaces, git worktrees, custom commands (config.toml + project overrides) and
  # agent panes.
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
    workspace_picker = "ctrl+p"
    navigate_workspace_up = "k"
    navigate_workspace_down = "j"
    previous_workspace = "ctrl+["
    next_workspace = "ctrl+]"
    previous_agent = "ctrl+{"
    next_agent = "ctrl+}"

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

  # Copy the plugin into a stable, writable directory and register it with
  # herdr, idempotently (only links when 'herdr-picker' is not present).
  home.activation.herdrPickerPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pluginDir="$HOME/.config/herdr/plugins-managed/picker"
    mkdir -p "$pluginDir"
    cp -f "${./herdr-plugins/picker/herdr-plugin.toml}" "$pluginDir/herdr-plugin.toml"
    cp -f "${./herdr-plugins/picker/launcher.sh}" "$pluginDir/launcher.sh"
    chmod +x "$pluginDir/launcher.sh"

    # Repo-managed picker settings -> plugin config dir (real, editable file;
    # a store symlink would be read-only). herdr seeds nothing if this exists.
    pickerCfg="$HOME/.config/herdr/plugins/config/herdr-picker"
    mkdir -p "$pickerCfg"
    cp -f "${./herdr-plugins/picker/config.toml}" "$pickerCfg/config.toml"

    herdrBin="$(command -v herdr 2>/dev/null || true)"
    [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
    if [ -x "$herdrBin" ]; then
      if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-picker"; then
        "$herdrBin" plugin link "$pluginDir" >/dev/null 2>&1 || true
      fi
    fi
  '';
}
