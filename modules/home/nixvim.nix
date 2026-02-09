{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.nixvim.homeModules.nixvim
  ];

  programs.nixvim = {
    enable = true;
    defaultEditor = true;

    # Global settings
    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

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
      foldmethod = "expr";
      foldexpr = "nvim_treesitter#foldexpr()";
      foldenable = false;
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

    # Plugins
    plugins = {
      # File explorer
      neo-tree = {
        enable = true;
        settings = {
          enable_diagnostics = true;
          enable_git_status = true;
          enable_modified_markers = true;
        };
      };

      # Fuzzy finder
      telescope = {
        enable = true;
        keymaps = {
          "<leader>ff" = "find_files";
          "<leader>fg" = "live_grep";
          "<leader>fb" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fr" = "oldfiles";
        };
      };

      # Treesitter - Disabled temporarily to avoid Swift build dependency
      treesitter = {
        enable = false;
        # nixvimInjections = true;
        # folding.enable = true;
        # indent.enable = true;
        # incrementalSelection.enable = true;

        # Only install grammars we need (excludes Swift to avoid build issues)
        # grammarPackages = with config.programs.nixvim.plugins.treesitter.package.builtGrammars; [
        #   nix
        #   python
        #   javascript
        #   typescript
        #   tsx
        #   json
        #   yaml
        #   toml
        #   bash
        #   lua
        #   markdown
        #   markdown_inline
        #   html
        #   css
        #   rust
        #   go
        #   c
        #   cpp
        #   vim
        #   vimdoc
        #   regex
        #   comment
        # ];
      };

      # LSP
      lsp = {
        enable = true;
        servers = {
          # Nix
          nil_ls.enable = true;

          # Python
          ruff.enable = true;

          # JavaScript/TypeScript
          ts_ls.enable = true;

          # Lua
          lua_ls.enable = true;

          # JSON/YAML
          jsonls.enable = true;

          # Bash
          bashls.enable = true;

          # Markdown
          marksman.enable = true;
        };

        keymaps = {
          diagnostic = {
            "<leader>e" = "open_float";
            "[d" = "goto_prev";
            "]d" = "goto_next";
          };
          lspBuf = {
            "gd" = "definition";
            "gD" = "declaration";
            "gr" = "references";
            "gi" = "implementation";
            "K" = "hover";
            "<leader>ca" = "code_action";
            "<leader>rn" = "rename";
            "<leader>f" = "format";
          };
        };
      };

      # Completion
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings = {
          mapping = {
            "<C-Space>" = "cmp.mapping.complete()";
            "<C-d>" = "cmp.mapping.scroll_docs(-4)";
            "<C-f>" = "cmp.mapping.scroll_docs(4)";
            "<C-e>" = "cmp.mapping.close()";
            "<CR>" = "cmp.mapping.confirm({ select = true })";
            "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
            "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
          };
          sources = [
            { name = "nvim_lsp"; }
            { name = "path"; }
            { name = "buffer"; }
            { name = "luasnip"; }
          ];
        };
      };

      # Snippets
      luasnip.enable = true;

      # Git integration
      gitsigns = {
        enable = true;
        settings = {
          current_line_blame = true;
          signs = {
            add.text = "│";
            change.text = "│";
            delete.text = "_";
            topdelete.text = "‾";
            changedelete.text = "~";
            untracked.text = "┆";
          };
        };
      };

      # Status line
      lualine = {
        enable = true;
        globalstatus = true;
        theme = "tokyonight";
      };

      # Buffer line
      bufferline = {
        enable = true;
        diagnostics = "nvim_lsp";
        separatorStyle = "slant";
      };

      # Auto pairs
      nvim-autopairs.enable = true;

      # Comments
      comment.enable = true;

      # Indent guides
      indent-blankline = {
        enable = true;
        settings = {
          scope.enabled = true;
        };
      };

      # Which-key (keybinding help)
      which-key = {
        enable = true;
        registrations = {
          "<leader>f" = "Find";
          "<leader>c" = "Code";
          "<leader>r" = "Rename";
          "<leader>g" = "Git";
          "<leader>t" = "Terminal";
        };
      };

      # Terminal
      toggleterm = {
        enable = true;
        settings = {
          direction = "float";
          float_opts = {
            border = "curved";
          };
        };
      };

      # Markdown preview - Disabled to avoid build dependencies
      markdown-preview.enable = false;

      # Todo comments - Disabled to avoid build dependencies
      todo-comments.enable = false;

      # Auto-save - Disabled to avoid build dependencies
      auto-save.enable = false;

      # Surround
      nvim-surround.enable = true;

      # Web devicons
      web-devicons.enable = true;

      # Colorizer (show colors in CSS/etc)
      nvim-colorizer = {
        enable = true;
        userDefaultOptions = {
          names = false;
        };
      };

      # Lazygit integration
      lazygit = {
        enable = true;
      };
    };

    # Key mappings
    keymaps = [
      # General
      {
        mode = "n";
        key = "<leader>w";
        action = "<cmd>w<cr>";
        options = {
          desc = "Save file";
        };
      }
      {
        mode = "n";
        key = "<leader>q";
        action = "<cmd>q<cr>";
        options = {
          desc = "Quit";
        };
      }
      {
        mode = "n";
        key = "<Esc>";
        action = "<cmd>nohlsearch<cr>";
        options = {
          desc = "Clear search highlight";
        };
      }

      # Better window navigation
      {
        mode = "n";
        key = "<C-h>";
        action = "<C-w>h";
        options = {
          desc = "Go to left window";
        };
      }
      {
        mode = "n";
        key = "<C-j>";
        action = "<C-w>j";
        options = {
          desc = "Go to lower window";
        };
      }
      {
        mode = "n";
        key = "<C-k>";
        action = "<C-w>k";
        options = {
          desc = "Go to upper window";
        };
      }
      {
        mode = "n";
        key = "<C-l>";
        action = "<C-w>l";
        options = {
          desc = "Go to right window";
        };
      }

      # Resize windows
      {
        mode = "n";
        key = "<C-Up>";
        action = "<cmd>resize +2<cr>";
        options = {
          desc = "Increase window height";
        };
      }
      {
        mode = "n";
        key = "<C-Down>";
        action = "<cmd>resize -2<cr>";
        options = {
          desc = "Decrease window height";
        };
      }
      {
        mode = "n";
        key = "<C-Left>";
        action = "<cmd>vertical resize -2<cr>";
        options = {
          desc = "Decrease window width";
        };
      }
      {
        mode = "n";
        key = "<C-Right>";
        action = "<cmd>vertical resize +2<cr>";
        options = {
          desc = "Increase window width";
        };
      }

      # Buffer navigation
      {
        mode = "n";
        key = "<S-h>";
        action = "<cmd>bprevious<cr>";
        options = {
          desc = "Previous buffer";
        };
      }
      {
        mode = "n";
        key = "<S-l>";
        action = "<cmd>bnext<cr>";
        options = {
          desc = "Next buffer";
        };
      }
      {
        mode = "n";
        key = "<leader>bd";
        action = "<cmd>bdelete<cr>";
        options = {
          desc = "Delete buffer";
        };
      }

      # Move lines
      {
        mode = "n";
        key = "<A-j>";
        action = "<cmd>m .+1<cr>==";
        options = {
          desc = "Move line down";
        };
      }
      {
        mode = "n";
        key = "<A-k>";
        action = "<cmd>m .-2<cr>==";
        options = {
          desc = "Move line up";
        };
      }
      {
        mode = "v";
        key = "<A-j>";
        action = ":m '>+1<cr>gv=gv";
        options = {
          desc = "Move selection down";
        };
      }
      {
        mode = "v";
        key = "<A-k>";
        action = ":m '<-2<cr>gv=gv";
        options = {
          desc = "Move selection up";
        };
      }

      # Stay in indent mode
      {
        mode = "v";
        key = "<";
        action = "<gv";
        options = {
          desc = "Indent left";
        };
      }
      {
        mode = "v";
        key = ">";
        action = ">gv";
        options = {
          desc = "Indent right";
        };
      }

      # Neo-tree
      {
        mode = "n";
        key = "<leader>e";
        action = "<cmd>Neotree toggle<cr>";
        options = {
          desc = "Toggle file explorer";
        };
      }

      # Terminal
      {
        mode = "n";
        key = "<leader>tf";
        action = "<cmd>ToggleTerm direction=float<cr>";
        options = {
          desc = "Toggle floating terminal";
        };
      }
      {
        mode = "n";
        key = "<leader>th";
        action = "<cmd>ToggleTerm direction=horizontal<cr>";
        options = {
          desc = "Toggle horizontal terminal";
        };
      }
      {
        mode = "n";
        key = "<leader>tv";
        action = "<cmd>ToggleTerm direction=vertical<cr>";
        options = {
          desc = "Toggle vertical terminal";
        };
      }

      # Git
      {
        mode = "n";
        key = "<leader>gg";
        action = "<cmd>LazyGit<cr>";
        options = {
          desc = "Open LazyGit";
        };
      }
      {
        mode = "n";
        key = "<leader>gb";
        action = "<cmd>Gitsigns blame_line<cr>";
        options = {
          desc = "Git blame line";
        };
      }
      {
        mode = "n";
        key = "<leader>gp";
        action = "<cmd>Gitsigns preview_hunk<cr>";
        options = {
          desc = "Preview hunk";
        };
      }
      {
        mode = "n";
        key = "<leader>gr";
        action = "<cmd>Gitsigns reset_hunk<cr>";
        options = {
          desc = "Reset hunk";
        };
      }
    ];

    # Auto commands
    autoCmd = [
      # Highlight yanked text
      {
        event = "TextYankPost";
        pattern = "*";
        callback = {
          __raw = ''
            function()
              vim.highlight.on_yank({ timeout = 200 })
            end
          '';
        };
      }

      # Remove trailing whitespace on save
      {
        event = "BufWritePre";
        pattern = "*";
        command = "%s/\\s\\+$//e";
      }

      # Auto-format on save for specific filetypes
      {
        event = "BufWritePre";
        pattern = [
          "*.nix"
          "*.lua"
          "*.py"
          "*.js"
          "*.ts"
          "*.json"
          "*.md"
        ];
        callback = {
          __raw = ''
            function()
              vim.lsp.buf.format({ async = false })
            end
          '';
        };
      }
    ];

    # Extra plugins (not in nixvim)
    extraPlugins = with pkgs.vimPlugins; [
      vim-sleuth # Auto-detect indentation
    ];

    # Extra configuration (raw Lua)
    extraConfigLua = ''
      -- Additional Lua configuration
      vim.opt.fillchars = { eob = " " }

      -- Better diff colors
      vim.cmd([[
        highlight DiffAdd guifg=#9ece6a guibg=#283b4d
        highlight DiffChange guifg=#7aa2f7 guibg=#283b4d
        highlight DiffDelete guifg=#f7768e guibg=#283b4d
      ]])
    '';
  };

  # Shell aliases
  programs.zsh.shellAliases = {
    v = "nvim";
    vi = "nvim";
    vim = "nvim";
  };
}
