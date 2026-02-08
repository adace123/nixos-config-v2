# Neovim Configuration (nvf)

This directory contains a modular Neovim configuration using the [nvf](https://github.com/notashelf/nvf) framework. The configuration has been split into logical modules for easier maintenance and navigation.

## Structure

```
modules/home/nvf/
├── README.md              # This file
├── default.nix            # Main entry point, imports all submodules
├── plugins.nix            # Custom plugin definitions (telescope-tabs)
├── core-settings.nix      # Basic vim settings, LSP, languages
├── completion.nix         # blink-cmp configuration
├── ui.nix                 # UI/visuals, terminal, which-key
├── keybindings.nix        # All keymaps (400+ lines)
├── extra-plugins.nix      # 12 extra plugins with Lua setup
├── lua-config.nix         # luaConfigRC sections
└── packages.nix           # Extra packages (lazygit, yazi, etc)
```

## Module Overview

### default.nix
Main entry point that:
- Imports the nvf home-manager module
- Imports all submodules in the correct order
- Enables the nvf program
- Defines shell aliases for nvim

### plugins.nix
Defines custom plugins that aren't available in nixpkgs:
- `telescope-tabs` - Tab picker for Telescope

Exports these via `_module.args.customPlugins` for use by other modules.

### core-settings.nix
Core Neovim configuration:
- Leader key (space)
- Basic settings (line numbers, search, splits, etc.)
- Theme and statusline (lualine)
- File tree (neo-tree)
- Telescope base configuration
- Git integration (gitsigns)
- LSP configuration
- Language servers:
  - Python: basedpyright (LSP) + ruff (formatter)
  - Nix: nixd

### completion.nix
Autocompletion using blink-cmp:
- Keybindings for completion menu
- Sources (LSP, path, buffer)
- Command line completion
- Menu and documentation settings

### ui.nix
Visual and UI configuration:
- Comments (comment-nvim)
- UI settings (illuminate, borders)
- Visuals (web-devicons, indent-blankline)
- Terminal (toggleterm)
- Which-key bindings and labels
- Flash.nvim for quick navigation

### keybindings.nix
All keybindings organized by mode:
- **Insert mode**: jk/kj to escape
- **Normal mode**:
  - General editing (quit, save, redo, copy)
  - Scrolling and centering
  - Terminal toggle (Ctrl+A, Ctrl+F)
  - Window navigation and resize
  - Buffer navigation
  - Line movement (Alt+j/k)
  - Neo-tree (leader+e)
  - Yazi file manager (-)
  - Telescope (leader+f prefix)
  - UI (leader+u prefix)
  - Splits (leader+s prefix)
  - Markdown (leader+m prefix)
  - Terminal (leader+t prefix)
  - Tab navigation (Ctrl+]/[, leader+t prefix)
  - Git (leader+g prefix, {/} for hunks)
  - Flash navigation (s/S)
- **Visual mode**: Flash, move selection, indent, git
- **Terminal mode**: Toggle terminal

### extra-plugins.nix
Additional plugins with custom Lua configuration:
- **vim-sleuth**: Auto-detect indentation
- **nvim-autopairs**: Auto-close brackets/quotes
- **lazygit-nvim**: LazyGit integration
- **persistence-nvim**: Session management (auto-save/restore)
- **catppuccin-nvim**: Catppuccin colorscheme (active)
- **kanagawa-nvim**: Kanagawa colorscheme
- **markview-nvim**: Markdown rendering
- **tabby-nvim**: Custom tab line
- **telescope-tabs**: Tab picker (uses custom plugin)
- **nvim-treesitter-textobjects**: Text objects
- **sidekick-nvim**: Custom built plugin
- **yazi-nvim**: Yazi file manager integration

### lua-config.nix
Raw Lua configuration snippets:
- Clipboard integration (system clipboard)
- Highlight on yank
- Trim trailing whitespace on save
- Better diff highlighting
- Misc vim options (fillchars, tabstop, etc.)
- Custom AI terminals (Claude, Gemini, Copilot)
- Toggleterm auto-insert mode
- Blink-cmp command line integration
- Auto-reload files on change

### packages.nix
External packages needed for plugins:
- lazygit
- yazi (file manager)
- ruff (Python formatter)
- basedpyright (Python LSP)
- nixd (Nix LSP)

## How to Customize

### Add a New Plugin

1. If it's a standard nixpkgs plugin, add it to `extra-plugins.nix`:
```nix
my-plugin = {
  package = my-plugin;
  setup = ''
    require("my-plugin").setup({})
  '';
};
```

2. If it's a custom plugin not in nixpkgs, add it to `plugins.nix`:
```nix
my-custom-plugin = pkgs.vimUtils.buildVimPlugin {
  name = "my-custom-plugin";
  src = pkgs.fetchFromGitHub { ... };
};
```
Then use it in `extra-plugins.nix` via `customPlugins.my-custom-plugin`.

### Add a New Keybinding

Edit `keybindings.nix` and add to the appropriate mode section:
```nix
"<leader>x" = {
  action = "<cmd>MyCommand<cr>";
  desc = "My description";
};
```

### Change Core Settings

Edit `core-settings.nix` for:
- Vim options and behavior
- LSP settings
- Language server configuration
- Telescope settings
- Git settings

### Modify UI/Appearance

Edit `ui.nix` for:
- Visual elements (borders, icons, indent guides)
- Terminal configuration
- Which-key labels
- Flash.nvim settings

### Add Lua Configuration

Edit `lua-config.nix` to add new Lua snippets:
```nix
my-config = ''
  -- Your Lua code here
  vim.opt.mysetting = true
'';
```

### Change Completion Behavior

Edit `completion.nix` to modify:
- Completion keybindings
- Sources
- Menu appearance
- Documentation behavior

### Add External Packages

Edit `packages.nix` to add tools needed by your plugins:
```nix
extraPackages = with pkgs; [
  existing-package
  my-new-tool
];
```

## Key Features

- **Leader key**: Space
- **Escape alternatives**: jk or kj in insert mode
- **File navigation**:
  - `leader+e` for Neo-tree
  - `-` for Yazi file manager
  - `leader+ff` for Telescope file finder
- **Search**: `leader+fg` or `leader+w` for live grep
- **Terminal**: `Ctrl+A` or `Ctrl+F` to toggle floating terminal
- **Tabs**: `Ctrl+]` / `Ctrl+[` to cycle tabs
- **Git**: `leader+gg` for LazyGit, `leader+g*` for various git operations
- **Sessions**: Auto-saves and restores sessions per directory
- **AI**: `leader+ac` (Claude), `leader+ag` (Gemini), `leader+ap` (Copilot)

## Building and Testing

To rebuild with your changes:
```bash
darwin-rebuild switch --flake .
```

Or to test without switching:
```bash
darwin-rebuild build --flake .
```

## Architecture Notes

- **Module Merging**: NixOS automatically deep-merges all `programs.nvf.settings.vim.*` across imported modules
- **Import Order**: `plugins.nix` must be imported first as it exports `customPlugins` via `_module.args`
- **No Duplication**: Each concern is in its own file - no settings are duplicated across modules
