_: {
  home.file.".config/1Password/ssh/agent.toml".text = ''
    [[ssh-keys]]
    vault = "Employee"
    item = "Work SSH Key"

    [[ssh-keys]]
    vault = "Development"
    item = "GitHub SSH Key"
  '';
}
