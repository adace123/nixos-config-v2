{ pkgs, ... }:
{
  programs.nixvim = {
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
          "<leader>fr" = "oldfiles";
          "<leader>fg" = "live_grep";
          "<leader>fd" = "diagnostics";
          "<leader>fb" = "buffers";
          "<leader>fh" = "help_tags";
          "<leader>fR" = "resume";
          "<leader>gf" = "git_files";
          "<leader>gc" = "git_commits";
          "<leader>gB" = "git_branches";
          "<leader>gq" = "git_status";
        };
      };

      # Treesitter - selective grammars (excludes Swift to avoid build issues)
      treesitter = {
        enable = true;
        nixvimInjections = true;
        folding = {
          enable = true;
        };
        indent.enable = true;
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          nix
          python
          javascript
          typescript
          tsx
          json
          yaml
          toml
          bash
          lua
          markdown
          markdown_inline
          html
          css
          rust
          go
          c
          cpp
          vim
          vimdoc
          regex
          comment
        ];
      };

      # LSP
      lsp = {
        enable = true;
        servers = {
          # Nix
          nixd.enable = true;

          # Python (type checking + linting)
          basedpyright.enable = true;
          ruff = {
            enable = true;
            settings = {
              cmd = [
                "${pkgs.ruff}/bin/ruff"
                "server"
                "--preview"
              ];
            };
          };

          # JavaScript/TypeScript
          ts_ls.enable = true;

          # Lua
          lua_ls.enable = true;

          # JSON
          jsonls.enable = true;

          # YAML
          yamlls.enable = true;

          # Bash
          bashls.enable = true;

          # Markdown
          marksman.enable = true;

          # Just (justfile)
          just.enable = true;
        };

        keymaps = {
          diagnostic = {
            "<leader>ld" = "open_float";
            "[d" = "goto_prev";
            "]d" = "goto_next";
          };
          lspBuf = {
            "gd" = "definition";
            "gD" = "declaration";
            "gr" = "references";
            "gi" = "implementation";
            "K" = "hover";
            "<leader>la" = "code_action";
            "<leader>lr" = "rename";
            "<leader>lf" = "format";
          };
        };
      };

      # Formatting via conform (single format-on-save path)
      conform-nvim = {
        enable = true;
        settings = {
          formatters_by_ft = {
            nix = [ "nixfmt" ];
            yaml = [ "yamlfmt" ];
            json = [ "jq" ];
            javascript = [ "prettierd" ];
            typescript = [ "prettierd" ];
            javascriptreact = [ "prettierd" ];
            typescriptreact = [ "prettierd" ];
            lua = [ "stylua" ];
            python = [ "ruff_format" ];
            terraform = [ "tofu_fmt" ];
            tf = [ "tofu_fmt" ];
            "terraform-vars" = [ "tofu_fmt" ];
            sh = [ "shfmt" ];
            bash = [ "shfmt" ];
            "_" = [ "trim_whitespace" ];
          };
          default_format_opts = {
            lsp_format = "fallback";
          };
          format_on_save = {
            lsp_format = "fallback";
            timeout_ms = 1000;
          };
          formatters = {
            yamlfmt = {
              command = "yamlfmt";
              args = [ "-" ];
            };
            jq = {
              command = "jq";
              args = [ "." ];
            };
          };
        };
      };

      # Completion
      blink-cmp = {
        enable = true;
        settings = {
          cmdline = {
            enabled = true;
            keymap = {
              "<CR>" = [
                "accept_and_enter"
                "fallback"
              ];
              "<Tab>" = [
                "show_and_insert_or_accept_single"
                "select_next"
              ];
              "<S-Tab>" = [
                "show_and_insert_or_accept_single"
                "select_prev"
              ];
            };
            completion = {
              menu = {
                auto_show = true;
                draw = {
                  columns = [
                    [
                      "label"
                      "label_description"
                    ]
                  ];
                };
              };
            };
          };
          completion = {
            accept.auto_brackets.enabled = true;
            documentation = {
              auto_show = true;
              auto_show_delay_ms = 200;
            };
            ghost_text.enabled = true;
          };
          sources = {
            default = [
              "lsp"
              "path"
              "snippets"
              "buffer"
            ];
            per_filetype = {
              gitcommit = [
                "git"
                "buffer"
              ];
              gitrebase = [
                "git"
                "buffer"
              ];
            };
            providers = {
              git = {
                module = "blink-cmp-git";
                name = "Git";
                score_offset = 100;
                opts = {
                  commit = { };
                  git_centers = {
                    git_hub = { };
                  };
                };
              };
              buffer.score_offset = -7;
            };
          };
          keymap = {
            preset = "enter";
            "<C-space>" = [
              "show"
              "show_documentation"
              "hide_documentation"
            ];
            "<C-e>" = [
              "hide"
              "fallback"
            ];
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
            "<C-b>" = [
              "scroll_documentation_up"
              "fallback"
            ];
            "<C-f>" = [
              "scroll_documentation_down"
              "fallback"
            ];
          };
          appearance = {
            use_nvim_cmp_as_default = true;
            nerd_font_variant = "mono";
          };
        };
      };
      blink-cmp-git.enable = true;

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
        settings = {
          options = {
            theme = "tokyonight";
            globalstatus = true;
          };
        };
      };

      # Buffer line
      bufferline = {
        enable = true;
        settings = {
          options = {
            diagnostics = "nvim_lsp";
          };
        };
      };
      # Auto pairs
      nvim-autopairs.enable = true;

      # Comments
      comment.enable = true;

      # Indent guides
      indent-blankline = {
        enable = true;
        settings = {
          indent = {
            char = "│";
            tab_char = "│";
          };
          scope.enabled = true;
          exclude = {
            filetypes = [
              "help"
              "alpha"
              "dashboard"
              "neo-tree"
              "Trouble"
              "lazy"
              "mason"
              "notify"
              "toggleterm"
              "lazyterm"
            ];
          };
        };
      };

      # Which-key (keybinding help)
      which-key = {
        enable = true;
        settings = {
          preset = "modern";
          delay = 200;
          spec = [
            {
              __unkeyed-1 = "<leader>b";
              group = "Buffers";
            }
            {
              __unkeyed-1 = "<leader>f";
              group = "Find";
            }
            {
              __unkeyed-1 = "<leader>g";
              group = "Git";
            }
            {
              __unkeyed-1 = "<leader>l";
              group = "LSP";
            }
            {
              __unkeyed-1 = "<leader>m";
              group = "Markdown";
            }
            {
              __unkeyed-1 = "<leader>q";
              group = "Session";
            }
            {
              __unkeyed-1 = "<leader>s";
              group = "Splits";
            }
            {
              __unkeyed-1 = "<leader>t";
              group = "Terminal";
            }
            {
              __unkeyed-1 = "<leader>x";
              group = "Diagnostics";
            }
          ];
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

      # Markdown rendering
      markview = {
        enable = true;
        settings = {
          preview = {
            enable = true;
            enable_hybrid_mode = true;
            icon_provider = "devicons";
          };
        };
      };

      # Surround
      nvim-surround.enable = true;

      # Web devicons
      web-devicons.enable = true;

      # Colorizer (show colors in CSS/etc)
      colorizer = {
        enable = true;
        settings = {
          user_default_options = {
            names = false;
          };
        };
      };

      # Lazygit integration
      lazygit = {
        enable = true;
      };

      # Flash navigation (quick jump)
      flash = {
        enable = true;
        settings = {
          modes = {
            search = {
              enabled = false;
            };
            char = {
              enabled = true;
            };
          };
        };
      };

      # Highlight same word under cursor
      illuminate.enable = true;

      # Workspace diagnostics list
      trouble = {
        enable = true;
        settings = {
          auto_close = true;
          auto_preview = true;
          focus = true;
          follow = true;
          win = {
            position = "bottom";
            size = 12;
          };
        };
      };

      # Yazi file manager integration
      yazi.enable = true;
    };

    # Extra plugins (not natively in nixvim)
    extraPlugins = with pkgs.vimPlugins; [
      vim-sleuth
      persistence-nvim
      plenary-nvim
      dashboard-nvim
    ];

  };
}
