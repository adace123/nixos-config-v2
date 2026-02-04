{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Git configuration
  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "aaron.feigenbaum";
        email = "noreply@github.com";
        # Signing key from 1Password
        signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH6NoE7HzOLf05FzjkbsQQkMSbe6AJEm2fgNZeaO6RAe";
      };

      init = {
        defaultBranch = "main";
      };

      pull = {
        rebase = false;
      };

      core = {
        excludesfile = "~/.config/git/ignore";
      };

      commit = {
        gpgsign = true;
      };

      gpg = {
        format = "ssh";
      };

      "gpg \"ssh\"" = {
        # Use 1Password for SSH signing
        program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
      };
    };

    # Conditional includes for work projects
    includes = [
      {
        condition = "gitdir:~/Projects/work/";
        path = "~/.config/git/work-config"; # Private file on my laptop
      }
    ];
  };

  # SSH configuration
  programs.ssh = {
    enable = true;

    # Disable default config and set explicitly
    enableDefaultConfig = false;

    matchBlocks = {
      # Default settings for all hosts
      "*" = {
        serverAliveInterval = 60;
        serverAliveCountMax = 3;
        controlMaster = "auto";
        controlPath = "~/.ssh/sockets/%r@%h-%p";
        controlPersist = "600";
        identityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
      };

      "github.com" = {
        hostname = "github.com";
        user = "git";
        # identityFile managed by 1Password SSH agent
      };
    };

    # Include private SSH config for work servers
    # This file is not tracked in git and stays only on your laptop
    extraConfig = ''
      Include ~/.ssh/work-config
    '';
  };

  # Workaround for Zed (and its bundled npm modules) creating ~/.gitconfig as a directory
  # This file redirects to the actual config managed by home-manager at ~/.config/git/config
  home.file.".gitconfig".text = ''
    [include]
      path = ~/.config/git/config
  '';

  # Global gitignore
  home.file.".config/git/ignore".text = ''
    # Python
    __pycache__/
    *.py[cod]
    *$py.class
    *.so
    .Python
    build/
    develop-eggs/
    dist/
    downloads/
    eggs/
    .eggs/
    lib/
    lib64/
    parts/
    sdist/
    var/
    wheels/
    *.egg-info/
    .installed.cfg
    *.egg
    MANIFEST
    .venv/
    env/
    venv/
    ENV/
    .uv/
    .coverage
    .pytest_cache/
    .mypy_cache/
    .ipynb_checkpoints

    # Node.js
    node_modules/
    npm-debug.log*
    yarn-debug.log*
    yarn-error.log*
    package-lock.json
    yarn.lock
    pnpm-lock.yaml
    bun.lockb
    .bun/
    dist/
    build/
    out/
    .next/
    .nuxt/
    .cache/
    *.tsbuildinfo
    coverage/

    # Environment files
    .env
    .env*.local

    # OS files
    .DS_Store
    Thumbs.db

    # Editor directories
    .vscode/
    .idea/
    *.swp
    *.swo
    *~

    # Logs
    logs/
    *.log
  '';

  # Create example work config files (these won't be managed, just examples)
  home.file.".ssh/work-config.example".text = ''
    # Example work SSH configuration
    # Copy this to ~/.ssh/work-config and update with your actual work git server

    # Example for work GitLab/GitHub Enterprise/Bitbucket
    # When using 1Password SSH agent, identity is managed automatically
    Host work-git gitlab-work github-enterprise
      HostName git.yourcompany.com
      User git

    # You can add multiple work git servers here
    # Host another-work-git
    #   HostName git.another.com
    #   User git
  '';

  home.file.".config/git/work-config.example".text = ''
    # Example work git configuration
    # Copy this to ~/.config/git/work-config and customize

    [user]
      name = Aaron Feigenbaum
      email = your.work.email@company.com
      # Replace with your work public key from 1Password
      signingkey = ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIWorkKeyHere

    [core]
      # Any other work-specific git settings

    [url "git@work-git:"]
      # Automatically use work-git host for company repos
      insteadOf = https://git.yourcompany.com/
  '';
}
