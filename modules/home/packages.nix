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

    # Pre-commit tooling, so linting and `pre-commit run` also work in a shell
    # that never loaded the flake dev shell — the herdr-kanban dispatch tabs,
    # which skip direnv (modules/home/zsh.nix, docs/kanban.md). The hook
    # *entries* are absolute store paths in .pre-commit-config.yaml, so what a
    # bare shell misses is the runner and the linters AGENTS.md tells you to run
    # by hand (statix, deadnix, nixfmt and yamlfmt are already above).
    prek # Pre-commit runner the repo's git hooks use
    shellcheck # Shell script linter
    markdownlint-cli # Markdown linter

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
