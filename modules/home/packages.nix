{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # Development tools
    ripgrep
    fd
    gum
    jq
    yq
    htop
    btop # Better htop with more features
    k9s # Kubernetes CLI manager
    kubectx
    yazi # Modern terminal file manager
    tree
    direnv # Automatic environment loading
    just # Command runner
    yamlfmt # YAML formatter
    zoxide # Smart directory jumping
    glab
    nh # Nix helper for better rebuild/clean/search UX
    lazygit
    sshpass
    jujutsu
    lazyjj
    trivy
    fzf
    tailscale
    home-assistant-cli
    opentofu
    sops

    # Modern CLI replacements
    bat # cat replacement
    eza # ls replacement
    television # fuzzy finder

    # Zsh completions
    carapace # Multi-shell completion generator (aws, gh, kubectl, docker, etc.)
    nix-zsh-completions # Completions for Nix commands
    zsh-completions # Additional completion definitions

    # Zsh plugins
    zsh-autopair # Auto-close and delete matching delimiters
  ];
}
