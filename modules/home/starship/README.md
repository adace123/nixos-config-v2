# Starship Prompt Presets

This directory contains different Starship prompt configurations that you can use with your shell.

## Available Presets

### Default (in `default.nix`)
A feature-rich prompt with:
- Git branch and status with emoji indicators
- Programming language version displays (Node.js, Python, Rust, Go, etc.)
- Nix shell indicator
- Docker context
- Kubernetes context
- Command duration (for commands > 500ms)
- Current time display

### Minimal (`minimal.nix`)
A clean, fast prompt with only:
- Current directory (truncated)
- Git branch and status
- Nix shell indicator
- No language versions or extra info

### Nerd Font (`nerd-font.nix`)
A beautiful prompt that requires a Nerd Font with:
- All features from default preset
- Enhanced icons using Nerd Font symbols
- Better visual separation
- Username/hostname for SSH sessions
- Memory usage indicator
- Battery status

## How to Switch Presets

### Option 1: Edit `modules/home/default.nix`

Comment out the current starship configuration and import a preset:

```nix
# Comment out or remove the inline starship config
# programs.starship = { ... };

# Import a preset instead
imports = [
  ./starship/minimal.nix
  # or
  # ./starship/nerd-font.nix
];
```

### Option 2: Copy Settings

Copy the settings from any preset file into the `programs.starship.settings` section in `modules/home/default.nix`.

### Option 3: Create Your Own

1. Copy one of the preset files as a starting point
2. Modify the settings to your liking
3. Import your custom preset in `modules/home/default.nix`

## Customization Tips

### Change Prompt Character
```nix
character = {
  success_symbol = "[➜](bold green)";  # Change ➜ to any character
  error_symbol = "[✗](bold red)";
};
```

### Disable a Module
```nix
nodejs.disabled = true;
python.disabled = true;
```

### Change Colors
Available colors: black, red, green, yellow, blue, purple, cyan, white, or any 256-color code.

```nix
directory = {
  style = "bold blue";  # Change cyan to blue
};
```

### Add Custom Modules
```nix
env_var.CUSTOM_VAR = {
  symbol = "🔧 ";
  format = "with [$env_value]($style) ";
};
```

## Testing Your Configuration

After modifying your starship config:

```bash
# Apply changes
darwin-rebuild switch --flake .

# Or use just
just switch

# Restart your terminal or reload zsh
source ~/.zshrc
```

## Resources

- [Starship Official Docs](https://starship.rs/)
- [Configuration Reference](https://starship.rs/config/)
- [Nerd Fonts](https://www.nerdfonts.com/) - Required for nerd-font preset
- [Preset Gallery](https://starship.rs/presets/)

## Troubleshooting

### Icons not showing correctly
You need a Nerd Font installed. The darwin configuration already includes FiraCode and Meslo Nerd Fonts. Make sure your terminal is using one of these fonts.

### Prompt is slow
Try the minimal preset or disable modules you don't use:
```nix
nodejs.disabled = true;
docker_context.disabled = true;
kubernetes.disabled = true;
```

### Want to see what's enabled
```bash
starship config
```

### Reset to defaults
Remove the starship configuration from your home-manager config and rebuild.