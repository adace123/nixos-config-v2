# macOS Nix Configuration

A Nix flake-based configuration for managing macOS systems using
nix-darwin and home-manager.

## Prerequisites

1. Install Nix with flakes support:

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L \
     https://install.determinate.systems/nix | sh -s -- install
   ```

   Or use the official installer with flakes enabled:

   ```bash
   sh <(curl -L https://nixos.org/nix/install)

   # Then enable flakes
   mkdir -p ~/.config/nix
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

2. Make sure you're on macOS (this configuration only supports Darwin systems).

## Quick Start

**For first-time setup**, simply run the bootstrap script:

```bash
cd nixos-config-v2
./bootstrap.sh
```

This will:

- Check that Nix is installed
- Detect your hostname automatically
- Build and activate the nix-darwin configuration
- Set up all system and user packages

## Manual Setup

If you prefer to set things up manually or the bootstrap script doesn't work:

1. Update the hostname in `flake-parts/darwin.nix`:
   - Replace `enervee-ltqcw2y7pv` with your actual hostname (run `scutil --get LocalHostName`)
   - Update the username from `aaron` to your username
   - Change `aarch64-darwin` to `x86_64-darwin` if you're on an Intel Mac

2. Update user details in `modules/home/default.nix`:
   - Update Git username and email
   - Customize packages and shell configuration as needed

3. Build and activate the configuration:

   ```bash
   # First time setup (installs nix-darwin)
   nix build .#darwinConfigurations.<your-hostname>.system
   ./result/sw/bin/darwin-rebuild switch --flake .
   
   # After first time, you can use:
   darwin-rebuild switch --flake .
   ```

## Usage

### Updating the System

After making changes to your configuration:

```bash
darwin-rebuild switch --flake ~/.config/nixos-config-v2
```

Or use the convenient alias (configured in home-manager):

```bash
update
```

### Updating Dependencies

To update all flake inputs (nixpkgs, nix-darwin, home-manager):

```bash
nix flake update
darwin-rebuild switch --flake ~/.config/nixos-config-v2
```

To update a specific input:

```bash
nix flake lock --update-input nixpkgs
```

### Adding Packages

#### System-wide packages

Add packages to `modules/darwin/default.nix` in the
`environment.systemPackages` list.

#### User packages

Add packages to `modules/home/default.nix` in the `home.packages` list.

#### Homebrew packages

Add formulae (CLI tools), casks (GUI apps), or Mac App Store apps to
`modules/darwin/homebrew.nix`:

- **Formulae**: Add to the `brews` list
- **Casks**: Add to the `casks` list
- **Mac App Store**: Add to the `masApps` attribute set (requires app ID
  from `mas search "App Name"`)

Example:

```nix
brews = [
  "ffmpeg"
  "imagemagick"
];

casks = [
  "visual-studio-code"
  "rectangle"
];

masApps = {
  "Xcode" = 497799835;
};
```

### Rollback

If something goes wrong, you can rollback to a previous generation:

```bash
darwin-rebuild --list-generations
darwin-rebuild --rollback
```

## Structure

```text
.
├── flake.nix              # Main flake configuration
├── flake.lock             # Locked dependency versions
├── modules/
│   ├── darwin/
│   │   ├── default.nix    # macOS system configuration
│   │   └── homebrew.nix   # Homebrew packages and casks
│   └── home/
│       └── default.nix    # Home-manager user configuration
└── README.md              # This file
```

## What's Included

### System Configuration (nix-darwin)

- Nix daemon with flakes enabled
- Auto-optimization of Nix store
- macOS system defaults (Dock, Finder, keyboard)
- Touch ID for sudo authentication
- Multiple Nerd Fonts (FiraCode, JetBrains Mono, Meslo, and more)
- Zsh as default shell
- Homebrew integration with automatic cleanup

### User Configuration (home-manager)

- **Python**: Python 3.13/3.12/3.11, UV package manager, Ruff, Mypy, Poetry, IPython
- **Node.js**: Node 22, Bun, npm, yarn, pnpm, TypeScript, ESLint, Prettier
- **Git**: Configured with comprehensive .gitignore
- **Shell**: Zsh with Oh-My-Zsh, Starship prompt, autosuggestions, syntax highlighting
- **CLI Tools**: ripgrep, fd, bat, eza, fzf, jq, htop, tree, direnv, just
- **Window Manager**: AeroSpace (i3-like tiling for macOS)
- **Terminal**: Ghostty with custom configuration
- **System Info**: Fastfetch with creative boxed output

### Optional (Currently Disabled)

- **Nixvim**: Full Neovim configuration with LSP, Treesitter, Telescope, Neo-tree
  - *Note: Temporarily disabled to avoid Swift build dependency issues*
  - To enable: uncomment `./nixvim.nix` in `modules/home/default.nix`

## Work SSH Keys Setup

This configuration supports separate SSH keys for personal (GitHub) and
work repositories. All work repositories in `~/Projects/work/` will
automatically use your work SSH key.

### Initial Setup

1. **Run the setup script:**

   ```bash
   ./scripts/setup-work-ssh.sh
   ```

   This will:
   - Generate a work SSH key if needed (`~/.ssh/id_ed25519_work`)
   - Create example configuration files
   - Guide you through the setup process

2. **Configure your work git server:**

   Edit `~/.ssh/work-config` (not tracked in git) and add your work server
   details:

   ```ssh
   Host work-git gitlab-work
     HostName git.yourcompany.com
     User git
     IdentityFile ~/.ssh/id_ed25519_work
     IdentitiesOnly yes
   ```

3. **Configure work git settings:**

   Edit `~/.config/git/work-config` (not tracked in git):

   ```gitconfig
   [user]
     name = Aaron Feigenbaum
     email = aaron.feigenbaum@yourcompany.com

   [url "git@work-git:"]
     insteadOf = https://git.yourcompany.com/
   ```

4. **Add your work public key to your work git server:**

   ```bash
   cat ~/.ssh/id_ed25519_work.pub
   ```

### Work SSH Usage

- **Personal repos (anywhere):** Use your personal key automatically

   ```bash
   git clone git@github.com:username/repo.git
   ```

- **Work repos (in ~/Projects/work/):** Use your work key automatically

   ```bash
   git clone git@work-git:company/repo.git ~/Projects/work/repo
   ```

The configuration will automatically:

- Use your work SSH key for all repositories in `~/Projects/work/`
- Use your work email for commits in `~/Projects/work/`
- Use your personal SSH key and email everywhere else

### Files Not Tracked in Git

These files stay private on your laptop:

- `~/.ssh/work-config` - Your work git server hostname
- `~/.config/git/work-config` - Your work git email and settings
- `~/.ssh/id_ed25519_work` - Your work private key
- `~/.ssh/id_ed25519_work.pub` - Your work public key

Example files are created by home-manager at:

- `~/.ssh/work-config.example`
- `~/.config/git/work-config.example`

## Customization

Feel free to customize any part of the configuration:

- **System settings**: Modify `modules/darwin/default.nix`
- **User environment**: Modify `modules/home/default.nix`
- **Homebrew packages**: Modify `modules/darwin/homebrew.nix`
- **Add more modules**: Create new files in `modules/` and import them in `flake.nix`

## Known Issues

### Swift Build Dependency

Some packages (notably nixvim with all treesitter grammars) trigger Swift
builds from source, which can take a very long time or fail. To avoid this:

- Nixvim is currently disabled by default
- If you want to enable it, uncomment it in `modules/home/default.nix`
- Consider using a binary cache or accepting the long build time

### Deprecated Options

Recent nixpkgs versions have renamed several options:

- `nerdfonts` → `nerd-fonts` (now individual packages)
- `ruff-lsp` → `ruff` (LSP now built-in)
- Various home-manager Git options now use `settings` namespace

These have all been fixed in this configuration.

## Troubleshooting

### Bootstrap script fails

If the bootstrap script fails, try the manual setup steps in the README.

### Nix daemon issues

If you encounter issues with the Nix daemon, restart it:

```bash
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

### Path issues

Make sure `/run/current-system/sw/bin` is in your PATH. This should be
handled automatically by nix-darwin.

### Home-manager conflicts

If home-manager complains about existing files, you may need to backup and
remove conflicting dotfiles.

### "darwin-rebuild: command not found"

This means nix-darwin isn't installed yet. Run the `bootstrap.sh` script to
install it.

## Resources

- [nix-darwin documentation](https://github.com/LnL7/nix-darwin)
- [home-manager manual](https://nix-community.github.io/home-manager/)
- [Nix language basics](https://nixos.org/manual/nix/stable/language/)
- [Nixpkgs search](https://search.nixos.org/packages)

## License

This configuration is provided as-is for personal use. Modify as needed for
your own setup.
