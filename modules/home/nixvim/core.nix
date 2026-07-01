{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    # Global settings
    globals = {
      mapleader = " ";
      maplocalleader = " ";
      loaded_matchit = 1;
      loaded_netrw = 1;
      loaded_netrwPlugin = 1;
    };

    luaLoader.enable = true;

    performance.byteCompileLua.enable = true;

    # Reuse home-manager's pkgs instance instead of nixvim constructing its
    # own separate nixpkgs evaluation. Without this, nixvim's internal
    # neovim-unwrapped/luajit and our manually-added plugins (e.g.
    # plenary-nvim) can resolve to two different luajit derivations, causing
    # a `pkgs.buildEnv` collision ("two given paths contain a conflicting
    # subpath") when nixvim assembles the Lua package env.
    nixpkgs.useGlobalPackages = true;

    # Options
    opts = {
      # Line numbers
      number = true;
      relativenumber = true;

      # Tabs and indentation
      tabstop = 2;
      shiftwidth = 2;
      expandtab = true;
      autoindent = true;
      smartindent = true;

      # Line wrapping
      wrap = false;
      linebreak = true;

      # Search
      ignorecase = true;
      smartcase = true;
      hlsearch = true;
      incsearch = true;

      # Appearance
      termguicolors = true;
      signcolumn = "yes";
      cursorline = true;
      scrolloff = 8;
      sidescrolloff = 8;

      # Behavior
      mouse = "a";
      clipboard = "unnamedplus";
      undofile = true;
      backup = false;
      writebackup = false;
      swapfile = false;
      updatetime = 300;
      timeoutlen = 400;

      # Splits
      splitright = true;
      splitbelow = true;

      # Completion
      completeopt = "menu,menuone,noselect";

      # Folding
      foldmethod = "indent";
      foldenable = false;
      foldlevel = 99;
      foldlevelstart = 99;

      # Misc
      wildmenu = true;
      wildmode = "longest:full,full";
      sessionoptions = "blank,buffers,curdir,folds,globals,help,tabpages,winsize,winpos,terminal,localoptions";
      cmdheight = 1;
      autoread = true;
    };

    # Color scheme
    colorschemes.tokyonight = {
      enable = true;
      settings = {
        style = "night";
        transparent = true;
        terminal_colors = true;
      };
    };

  };

  # Extra packages needed for plugins/lsp
  home.packages = with pkgs; [
    lazygit
    yazi
    ruff
    basedpyright
    nixd
    deadnix
    statix
    nixfmt
    yamlfmt
    jq
    stylua
    prettierd
    shfmt
    opentofu
  ];

  # Shell aliases
  programs.zsh.shellAliases = {
    v = "nvim";
    vi = "nvim";
    vim = "nvim";
  };
}
