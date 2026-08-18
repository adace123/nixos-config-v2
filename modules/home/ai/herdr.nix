{ ... }:
{
  xdg.configFile."herdr/config.toml".text = ''
    onboarding = false

    [theme]
    name = "catppuccin"
    auto_switch = false

    [ui] 
    toast.delivery = "system"

    [[keys.command]]
    key = "prefix+l"
    type = "popup"
    command = "lazygit"
    description = "run lazygit"
    width = "80%"
    height = "80%"
  '';
}
