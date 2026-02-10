_: {
  programs.nvf.settings.vim = {
    # Vim aliases
    viAlias = true;
    vimAlias = true;

    # Leader key
    globals.mapleader = " ";

    # Basic settings
    lineNumberMode = "relNumber";
    preventJunkFiles = true;
    bell = "none";
    searchCase = "smart";

    # Vim options
    options = {
      autoindent = true;
      cmdheight = 1;
      updatetime = 300;
      tm = 400;
      splitbelow = true;
      splitright = true;
      mouse = "a";
      wildmenu = true;
      wildmode = "longest:full,full";
      sessionoptions = "blank,buffers,curdir,folds,globals,help,tabpages,winsize,winpos,terminal,localoptions";
      autoread = true;
    };

    # Appearance
    theme = {
      enable = false;
    };

    # Status line
    statusline.lualine = {
      enable = true;
      theme = "auto";
      globalStatus = true;
      activeSection.b = [
        ''
          {
            "filetype",
            colored = true,
            icon_only = true,
            icon = { align = 'left' }
          }
        ''
        ''
          {
            "filename",
            path = 1,
            symbols = {modified = ' ', readonly = ' '},
            separator = {right = ''}
          }
        ''
        ''
          {
            "",
            draw_empty = true,
            separator = { left = '', right = '' }
          }
        ''
      ];
    };

    # Tab line
    tabline.nvimBufferline.enable = true;

    # File tree
    filetree.neo-tree = {
      enable = true;
      setupOpts = {
        enable_diagnostics = true;
        enable_git_status = true;
      };
    };

    # Telescope
    telescope = {
      enable = true;
      setupOpts = {
        defaults = {
          mappings = {
            i = {
              "<esc>" = "close";
            };
          };
        };
        pickers = {
          colorscheme = {
            enable_preview = true;
          };
        };
      };
    };

    # Git
    git = {
      enable = true;
      gitsigns = {
        enable = true;
        codeActions.enable = true;
      };
    };

    # LSP
    lsp = {
      enable = true;
      formatOnSave = true;
      lspkind.enable = false;
      lightbulb.enable = false;
      lspSignature.enable = false;
      trouble.enable = false;
    };

    # Language servers
    languages = {
      enableFormat = true;
      enableTreesitter = true;
      enableExtraDiagnostics = false;

      # Python with ruff formatting and basedpyright
      python = {
        enable = true;
        lsp = {
          enable = true;
          servers = [ "basedpyright" ];
        };
        format = {
          enable = true;
          type = [ "ruff" ];
        };
      };

      # Nix
      nix = {
        enable = true;
        lsp = {
          enable = true;
          servers = [ "nixd" ];
        };
        format = {
          enable = true;
          type = [ "nixfmt" ];
        };
      };

      # YAML
      yaml = {
        enable = true;
        lsp = {
          enable = true;
          servers = [ "yaml-language-server" ];
        };
      };
    };

    # Formatter for YAML (and other languages)
    formatter.conform-nvim = {
      enable = true;
      setupOpts = {
        formatters_by_ft = {
          yaml = {
            "yamlfmt" = {
              __unkeyed-1 = "yamlfmt";
            };
          };
        };
        formatters = {
          yamlfmt = {
            command = "yamlfmt";
            args = [ "-" ];
          };
        };
      };
    };
  };
}
