{ ... }:
{
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
    workspace_picker = "ctrl+p"
    navigate_workspace_up = "k"
    navigate_workspace_down = "j"

    [[keys.command]]
    key = "prefix+l"
    type = "popup"
    command = "lazygit"
    description = "run lazygit"
    width = "80%"
    height = "80%"

    [[keys.command]]
    key = "prefix+C"
    type = "popup"
    command = "pi '/skill:commit-all'"
    description = "commit all changes"
    width = "80%"
    height = "80%"
  '';
}
