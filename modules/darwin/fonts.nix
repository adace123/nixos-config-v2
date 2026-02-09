{ pkgs, ... }:

{
  # Font configuration for macOS
  #
  # This module installs Nerd Fonts and other programming fonts system-wide.
  # Nerd Fonts are patched fonts with additional glyphs/icons for terminal prompts
  # like Starship, Powerlevel10k, etc.
  #
  # Installed Nerd Fonts:
  # - FiraCode: Popular monospace with ligatures
  # - JetBrainsMono: JetBrains IDE font
  # - Meslo: Apple's Menlo with powerline glyphs
  # - Hack: Clean, readable monospace
  # - SourceCodePro: Adobe's programming font
  # - CascadiaCode: Microsoft's Windows Terminal font
  # - Iosevka: Slender monospace font
  # - And more...
  #
  # To use in your terminal:
  # 1. iTerm2: Preferences → Profiles → Text → Font → Select a Nerd Font
  # 2. Terminal.app: Preferences → Profiles → Font → Select a Nerd Font
  # 3. Alacritty: Edit ~/.config/alacritty/alacritty.yml and set font.normal.family
  #
  # Recommended fonts for Starship:
  # - FiraCode Nerd Font
  # - JetBrainsMono Nerd Font
  # - Meslo LG Nerd Font
  #
  fonts = {
    # Install fonts system-wide
    packages = with pkgs; [
      # Nerd Fonts - Individual font packages
      nerd-fonts.fira-code # Popular monospace with ligatures
      nerd-fonts.jetbrains-mono # JetBrains IDE font
      nerd-fonts.meslo-lg # Apple's Menlo with powerline glyphs
      nerd-fonts.hack # Clean, readable monospace
      nerd-fonts.sauce-code-pro # Adobe's Source Code Pro
      nerd-fonts.droid-sans-mono # Google's Android font
      nerd-fonts.ubuntu-mono # Ubuntu's monospace font
      nerd-fonts.caskaydia-cove # Microsoft's Cascadia Code
      nerd-fonts.iosevka # Slender monospace font
      nerd-fonts.roboto-mono # Google's Roboto family

      # Apple SF Pro (System Fonts) - Already installed on macOS
      # But available via Homebrew casks if needed

      # Additional programming fonts
      fira-code # Non-patched FiraCode (for comparison)
      jetbrains-mono # Non-patched JetBrains Mono
      source-code-pro # Non-patched Source Code Pro

      # Icon fonts for terminal and UI
      font-awesome # Popular icon font
      material-icons # Google Material Design icons
      material-design-icons
    ];
  };
}
