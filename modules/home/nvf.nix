{
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    inputs.nvf.homeManagerModules.default
  ];

  programs.nvf = {
    enable = true;

    settings.vim = {
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
      };

      # Tab line
      tabline.nvimBufferline = {
        enable = true;
        setupOpts = {
          options = {
            mode = "buffers";
            separator_style = "slant";
            diagnostics = "nvim_lsp";
          };
        };
      };

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
        enableTreesitter = false;
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
        };
      };

      # Completion - using blink.cmp
      autocomplete.blink-cmp = {
        enable = true;
        setupOpts = {
          keymap = {
            preset = "default";
            "<C-space>" = [
              "show"
              "show_documentation"
              "hide_documentation"
            ];
            "<C-e>" = [ "hide" ];
            "<CR>" = [
              "accept"
              "fallback"
            ];
            "<Tab>" = [
              "select_next"
              "fallback"
            ];
            "<S-Tab>" = [
              "select_prev"
              "fallback"
            ];
            "<C-k>" = [
              "select_prev"
              "fallback"
            ];
            "<C-j>" = [
              "select_next"
              "fallback"
            ];
          };
          sources = {
            default = [
              "lsp"
              "path"
              "buffer"
            ];
          };
          cmdline = {
            sources = [ "cmdline" ];
          };
          completion = {
            trigger = {
              show_on_insert_on_trigger_character = true;
            };
            menu = {
              enabled = true;
              auto_show = true;
              draw = {
                columns = [
                  [ "kind_icon" ]
                  [
                    "label"
                    "label_description"
                  ]
                  [ "source_name" ]
                ];
              };
            };
            documentation = {
              auto_show = true;
              auto_show_delay_ms = 500;
            };
          };
        };
      };

      # Comments
      comments.comment-nvim.enable = true;

      # UI
      ui = {
        noice.enable = false;
        illuminate.enable = true;
        borders = {
          enable = true;
          globalStyle = "rounded";
        };
      };

      # Visuals
      visuals = {
        nvim-web-devicons.enable = true;
        indent-blankline = {
          enable = true;
          setupOpts.scope.enabled = true;
        };
      };

      # Terminal
      terminal.toggleterm = {
        enable = true;
        setupOpts = {
          direction = "float";
          float_opts.border = "curved";
          shell = "zsh";
          start_in_insert = true;
        };
      };

      # Which-key
      binds.whichKey = {
        enable = true;
        register = {
          "<leader>f" = "+Find/Diagnostics";
          "<leader>g" = "+Git";
          "<leader>t" = "+Terminal";
          "<leader>b" = "+Buffer";
          "<leader>c" = "+Code";
          "<leader>s" = "+Split";
          "<leader>m" = "+Markdown";
          "<leader>a" = "+AI";
        };
      };

      # Flash.nvim for quick navigation
      utility.motion.flash-nvim = {
        enable = true;
        setupOpts = {
          modes = {
            search = {
              enabled = true;
            };
            char = {
              enabled = true;
            };
          };
        };
      };

      # Keybindings
      maps = {
        insert = {
          # Exit insert mode with jk or kj
          "jk" = {
            action = "<Esc>";
          };
          "kj" = {
            action = "<Esc>";
          };
        };

        normal = {
          # General
          "<leader>q" = {
            action = "<cmd>q<cr>";
          };
          "<Esc>" = {
            action = "<cmd>nohlsearch<cr>";
          };
          "X" = {
            action = "<cmd>bdelete<cr>";
          };

          # Save commands
          "W" = {
            action = "<cmd>noautocmd w<cr>";
          };
          "<C-s>" = {
            action = "<cmd>w<cr>";
          };

          # Redo
          "U" = {
            action = "<C-r>";
          };

          # Copy operations
          "<leader>Y" = {
            action = "gg\"+yG";
          };
          "yy" = {
            action = "\"+yy";
          };

          # Scrolling with centering
          "<C-d>" = {
            action = "<C-d>zz";
          };
          "<C-u>" = {
            action = "<C-u>zz";
          };

          # Toggle terminal
          "<C-a>" = {
            action = "<cmd>ToggleTerm direction=float<cr>";
          };
          "<C-f>" = {
            action = "<cmd>ToggleTerm direction=float<cr>";
          };

          # Window navigation
          "<C-h>" = {
            action = "<C-w>h";
          };
          "<C-j>" = {
            action = "<C-w>j";
          };
          "<C-k>" = {
            action = "<C-w>k";
          };
          "<C-l>" = {
            action = "<C-w>l";
          };
          "<C-x>" = {
            action = "<cmd>close<cr>";
          };

          # Resize windows
          "<C-Up>" = {
            action = "<cmd>resize +2<cr>";
          };
          "<C-Down>" = {
            action = "<cmd>resize -2<cr>";
          };
          "<C-Left>" = {
            action = "<cmd>vertical resize -2<cr>";
          };
          "<C-Right>" = {
            action = "<cmd>vertical resize +2<cr>";
          };

          # Buffer navigation
          "<S-h>" = {
            action = "<cmd>bnext<cr>";
          };
          "<S-l>" = {
            action = "<cmd>bprevious<cr>";
          };
          "<leader>bd" = {
            action = "<cmd>bdelete<cr>";
          };

          # Move lines
          "<A-j>" = {
            action = "<cmd>m .+1<cr>==";
          };
          "<A-k>" = {
            action = "<cmd>m .-2<cr>==";
          };

          # Neo-tree
          "<leader>e" = {
            action = "<cmd>Neotree toggle<cr>";
          };

          # Telescope
          "<leader>ff" = {
            action = "<cmd>Telescope find_files<cr>";
          };
          "<leader>fg" = {
            action = "<cmd>Telescope live_grep<cr>";
          };
          "<leader>fw" = {
            action = "<cmd>Telescope live_grep<cr>";
          };
          "<leader>fb" = {
            action = "<cmd>Telescope buffers<cr>";
          };
          "<leader>fh" = {
            action = "<cmd>Telescope help_tags<cr>";
          };
          "<leader>fr" = {
            action = "<cmd>Telescope oldfiles<cr>";
          };
          "<leader>fd" = {
            action = "<cmd>Telescope diagnostics<cr>";
          };
          "<leader>." = {
            action = "<cmd>Telescope resume<cr>";
          };

          # UI
          "<leader>ut" = {
            action = "<cmd>Telescope colorscheme<cr>";
          };

          # Splits
          "<leader>sv" = {
            action = "<cmd>vsplit<cr>";
          };
          "<leader>sh" = {
            action = "<cmd>split<cr>";
          };

          # Markdown
          "<leader>mt" = {
            action = "<cmd>Markview toggle<cr>";
          };

          # Terminal
          "<leader>tf" = {
            action = "<cmd>ToggleTerm direction=float<cr>";
          };
          "<leader>th" = {
            action = "<cmd>ToggleTerm direction=horizontal<cr>";
          };
          "<leader>tv" = {
            action = "<cmd>ToggleTerm direction=vertical<cr>";
          };

          # Git
          "<leader>gg" = {
            action = "<cmd>LazyGit<cr>";
          };
          "<leader>gb" = {
            action = "<cmd>Gitsigns blame_line<cr>";
          };
          "<leader>gp" = {
            action = "<cmd>Gitsigns preview_hunk<cr>";
          };
          "<leader>gr" = {
            action = "<cmd>Gitsigns reset_hunk<cr>";
          };
          "<leader>gS" = {
            action = "<cmd>Gitsigns stage_buffer<cr>";
          };
          "<leader>gs" = {
            action = "<cmd>Gitsigns stage_hunk<cr>";
          };
          "<leader>gR" = {
            action = "<cmd>Gitsigns reset_buffer<cr>";
          };
          "<leader>gu" = {
            action = "<cmd>Gitsigns undo_stage_hunk<cr>";
          };
          "<leader>gU" = {
            action = "<cmd>Gitsigns reset_buffer_index<cr>";
          };
          "<leader>gd" = {
            action = "<cmd>Gitsigns diffthis<cr>";
          };
          "<leader>gtb" = {
            action = "<cmd>Gitsigns toggle_current_line_blame<cr>";
          };
          "<leader>gtd" = {
            action = "<cmd>Gitsigns toggle_deleted<cr>";
          };
          "}" = {
            action = "<cmd>Gitsigns next_hunk<cr>";
          };
          "{" = {
            action = "<cmd>Gitsigns prev_hunk<cr>";
          };

          # AI Sidekick
          "<leader>aa" = {
            action = "<cmd>lua require('sidekick.cli').toggle()<cr>";
          };
          "<leader>as" = {
            action = "<cmd>lua require('sidekick.cli').select()<cr>";
          };
          "<leader>ad" = {
            action = "<cmd>lua require('sidekick.cli').close()<cr>";
          };
          "<leader>ap" = {
            action = "<cmd>lua require('sidekick.cli').prompt()<cr>";
          };
          "<leader>af" = {
            action = "<cmd>lua require('sidekick.cli').send({ msg = '{file}' })<cr>";
          };
          "<C-.>" = {
            action = "<cmd>lua require('sidekick.cli').toggle()<cr>";
          };

          # Flash navigation
          "s" = {
            action = "<cmd>lua require('flash').jump()<cr>";
          };
          "S" = {
            action = "<cmd>lua require('flash').treesitter()<cr>";
          };
        };

        visual = {
          # Flash navigation
          "s" = {
            action = "<cmd>lua require('flash').jump()<cr>";
          };
          "S" = {
            action = "<cmd>lua require('flash').treesitter()<cr>";
          };
          # Move selection
          "<A-j>" = {
            action = ":m '>+1<cr>gv=gv";
          };
          "<A-k>" = {
            action = ":m '<-2<cr>gv=gv";
          };

          # Indent
          "<" = {
            action = "<gv";
          };
          ">" = {
            action = ">gv";
          };

          # Git - stage/reset selection
          "<leader>gs" = {
            action = "<cmd>Gitsigns stage_hunk<cr>";
          };
          "<leader>gr" = {
            action = "<cmd>Gitsigns reset_hunk<cr>";
          };

          # AI Sidekick - send selection
          "<leader>av" = {
            action = "<cmd>lua require('sidekick.cli').send({ msg = '{selection}' })<cr>";
          };
          "<leader>at" = {
            action = "<cmd>lua require('sidekick.cli').send({ msg = '{this}' })<cr>";
          };
        };

        terminal = {
          # Toggle terminal in terminal mode
          "<C-a>" = {
            action = "<C-\\><C-n><cmd>ToggleTerm<cr>";
          };
          "<C-f>" = {
            action = "<C-\\><C-n><cmd>ToggleTerm<cr>";
          };
        };
      };

      # Extra plugins and configuration
      extraPlugins = with pkgs.vimPlugins; {
        vim-sleuth = {
          package = vim-sleuth;
          setup = "-- Auto-detect indentation";
        };
        nvim-autopairs = {
          package = nvim-autopairs;
          setup = ''require("nvim-autopairs").setup({})'';
        };
        lazygit-nvim = {
          package = lazygit-nvim;
          setup = ''
            -- LazyGit setup
            vim.g.lazygit_floating_window_scaling_factor = 0.9
          '';
        };
        auto-session = {
          package = auto-session;
          setup = ''
            require("auto-session").setup({
              log_level = "error",
              auto_session_suppress_dirs = { "~/", "~/Downloads", "/" },
              auto_save_enabled = true,
              auto_restore_enabled = true,
            })
          '';
        };
        catppuccin-nvim = {
          package = catppuccin-nvim;
          setup = ''
            require("catppuccin").setup({
              flavour = "mocha",
              transparent_background = true,
            })
            vim.cmd.colorscheme("catppuccin")
          '';
        };
        kanagawa-nvim = {
          package = kanagawa-nvim;
          setup = ''
            require("kanagawa").setup({
              transparent = true,
            })
          '';
        };
        markview-nvim = {
          package = markview-nvim;
          setup = ''
            require("markview").setup({
              modes = { "n", "no", "c" },
              hybrid_modes = { "n" },
              callbacks = {
                on_enable = function(_, win)
                  vim.wo[win].conceallevel = 2;
                  vim.wo[win].concealcursor = "c";
                end
              }
            })
          '';
        };
        # zellij-nvim = {
        #   package = zellij-nvim;
        #   setup = ''
        #     -- zellij.nvim setup
        #     -- This allows seamless navigation between vim splits and zellij panes
        #     -- Use Ctrl-h/j/k/l to navigate
        #     require('zellij').setup({
        #       -- Optional: configure keybindings
        #       -- The plugin automatically sets up Ctrl-h/j/k/l navigation
        #     })
        #   '';
        # };
        sidekick-nvim = {
          package =
            (pkgs.vimUtils.buildVimPlugin {
              name = "sidekick-nvim";
              src = pkgs.fetchFromGitHub {
                owner = "folke";
                repo = "sidekick.nvim";
                rev = "main";
                sha256 = "sha256-ABuILCcKfYViZoFHaCepgIMLjvMEb/SBmGqGHUBucAM=";
              };
            }).overrideAttrs
              (old: {
                nvimRequireCheck = "sidekick";
              });
          setup = ''
            require("sidekick").setup({
              cli = {
                mux = {
                  backend = "zellij",
                  enabled = false,
                },
                win = {
                  layout = "float",
                  split = {
                    width = 80,
                  },
                },
              },
            })
          '';
        };
      };

      # Extra packages needed for plugins
      extraPackages = with pkgs; [
        lazygit
        ruff # Python linter/formatter
        basedpyright # Python type checker
        nixd # Nix language server
      ];

      # Extra Lua configuration
      luaConfigRC = {
        clipboard = ''
          vim.opt.clipboard:append("unnamedplus")
        '';

        highlight-yank = ''
          vim.api.nvim_create_autocmd('TextYankPost', {
            pattern = '*',
            callback = function()
              vim.highlight.on_yank({ timeout = 200 })
            end,
          })
        '';

        trim-whitespace = ''
          vim.api.nvim_create_autocmd('BufWritePre', {
            pattern = '*',
            command = [[%s/\s\+$//e]],
          })
        '';

        better-diff = ''
          vim.cmd([[
            highlight DiffAdd guifg=#9ece6a guibg=#283b4d
            highlight DiffChange guifg=#7aa2f7 guibg=#283b4d
            highlight DiffDelete guifg=#f7768e guibg=#283b4d
          ]])
        '';

        misc = ''
          vim.opt.fillchars = { eob = " " }
          vim.opt.tabstop = 2
          vim.opt.shiftwidth = 2
          vim.opt.signcolumn = "yes"
        '';

        toggleterm-insert-mode = ''
          -- Always enter insert mode when opening a terminal
          vim.api.nvim_create_autocmd("TermOpen", {
            pattern = "term://*toggleterm#*",
            callback = function()
              vim.cmd("startinsert")
            end,
          })
        '';

        blink-cmdline = ''
          -- Enable blink.cmp for command line
          vim.api.nvim_create_autocmd('CmdlineEnter', {
            callback = function()
              require('blink.cmp').show()
            end,
          })
        '';
      };
    };
  };

  # Shell aliases
  programs.zsh.shellAliases = {
    v = "nvim";
    vi = "nvim";
    vim = "nvim";
    nvim-clean = ''nvim --cmd "lua vim.g.auto_session_enabled = false"'';
  };
}
