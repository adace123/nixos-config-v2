{ ... }:
{
  programs.nixvim = {
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

      # Enter insert mode in terminal buffers
      {
        event = [
          "TermOpen"
          "BufEnter"
        ];
        pattern = "term://*toggleterm#*";
        callback = {
          __raw = ''
            function()
              vim.cmd("startinsert")
            end
          '';
        };
      }

      # Auto-reload files changed on disk
      {
        event = [
          "FocusGained"
          "BufEnter"
          "CursorHold"
          "CursorHoldI"
        ];
        pattern = "*";
        callback = {
          __raw = ''
            function()
              if vim.fn.mode() ~= 'c' then
                vim.cmd('checktime')
              end
            end
          '';
        };
      }

      # Notify when file changes on disk
      {
        event = "FileChangedShellPost";
        pattern = "*";
        callback = {
          __raw = ''
            function()
              vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.WARN)
            end
          '';
        };
      }
    ];

    # Extra configuration (raw Lua)
    extraConfigLua = ''
      -- Better diff colors (tokyonight)
      vim.cmd([[
        highlight DiffAdd guifg=#9ece6a guibg=#283b4d
        highlight DiffChange guifg=#7aa2f7 guibg=#283b4d
        highlight DiffDelete guifg=#f7768e guibg=#283b4d
      ]])

      -- Fillchars
      vim.opt.fillchars = { eob = " " }

      -- Persistence.nvim (session management)
      require("persistence").setup({
        dir = vim.fn.expand(vim.fn.stdpath("state") .. "/sessions/"),
        options = vim.opt.sessionoptions:get()
      })

      -- Helper to check if directory should be suppressed
      local function should_suppress()
        local cwd = vim.fn.getcwd()
        local suppress_dirs = { vim.fn.expand("~"), vim.fn.expand("~/Downloads"), "/" }
        for _, dir in ipairs(suppress_dirs) do
          if cwd == dir then
            return true
          end
        end
        return false
      end

      -- Auto-save session on exit
      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
          if not should_suppress() then
            require("persistence").save()
          end
        end,
      })

      -- Session keybindings
      vim.keymap.set("n", "<leader>qs", function()
        require("persistence").load()
      end, { desc = "Restore session" })

      vim.keymap.set("n", "<leader>ql", function()
        require("persistence").load({ last = true })
      end, { desc = "Restore last session" })

      vim.keymap.set("n", "<leader>qd", function()
        require("persistence").stop()
      end, { desc = "Don't save session" })
      -- ── Dashboard (startup screen) ──
      local db = require('dashboard')

      -- Custom ASCII banner (tokyonight neon vibe)
      local banner = {
        "                                                     ",
        "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗",
        "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║",
        "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║",
        "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║",
        "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║",
        "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝",
        "                                                     ",
      }

      -- TOTALLY_CUSTOM header (matches tokyonight palette)
      vim.api.nvim_create_autocmd("ColorScheme", {
        callback = function()
          vim.api.nvim_set_hl(0, "DashboardHeader", { fg = "#7aa2f7", bold = true })
          vim.api.nvim_set_hl(0, "DashboardCenter", { fg = "#c0caf5" })
          vim.api.nvim_set_hl(0, "DashboardShortcut", { fg = "#f7768e", bold = true })
          vim.api.nvim_set_hl(0, "DashboardFooter", { fg = "#565f89", italic = true })
          vim.api.nvim_set_hl(0, "DashboardKey", { fg = "#bb9af7", bold = true })
        end,
      })
      -- Apply immediately (colorscheme already loaded)
      vim.api.nvim_set_hl(0, "DashboardHeader", { fg = "#7aa2f7", bold = true })
      vim.api.nvim_set_hl(0, "DashboardCenter", { fg = "#c0caf5" })
      vim.api.nvim_set_hl(0, "DashboardShortcut", { fg = "#f7768e", bold = true })
      vim.api.nvim_set_hl(0, "DashboardFooter", { fg = "#565f89", italic = true })
      vim.api.nvim_set_hl(0, "DashboardKey", { fg = "#bb9af7", bold = true })

      db.setup({
        theme = 'doom',
        config = {
          header = banner,
          center = {
            {
              icon = '  ',
              key = 'f',
              desc = 'Find File        ',
              action = "Telescope find_files",
            },
            {
              icon = '  ',
              key = 'r',
              desc = 'Recent Files     ',
              action = "Telescope oldfiles",
            },
            {
              icon = '  ',
              key = 's',
              desc = 'Restore Session  ',
              action = function() require("persistence").load() end,
            },
            {
              icon = '  ',
              key = 'g',
              desc = 'Live Grep        ',
              action = "Telescope live_grep",
            },
            {
              icon = '  ',
              key = 'n',
              desc = 'New File         ',
              action = "enew",
            },
            {
              icon = '  ',
              key = 'g',
              desc = 'LazyGit          ',
              action = "LazyGit",
            },
            {
              icon = '  ',
              key = 'q',
              desc = 'Quit Neovim      ',
              action = "qa",
            },
          },
          footer = function()
            return {
              "",
              "⚡ Neovim v" .. vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
            }
          end,
        },
      })


      -- Telescope buffer delete helper
      local telescope = require('telescope')
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      local delete_buffer = function(prompt_bufnr)
        local current_picker = action_state.get_current_picker(prompt_bufnr)
        current_picker:delete_selection(function(selection)
          vim.api.nvim_buf_delete(selection.bufnr, { force = false })
        end)
      end

      telescope.setup({
        defaults = {
          mappings = {
            i = {
              ["<C-x>"] = delete_buffer,
              ["<Esc>"] = actions.close,
            },
            n = {
              ["<C-x>"] = delete_buffer,
            },
          },
        },
      })

      -- Built-in Tree-sitter incremental selection (Neovim 0.12+)
      local function ts_select(target)
        return function()
          vim.treesitter.select(target, vim.v.count1)
        end
      end

      vim.keymap.set("n", "<CR>", ts_select("parent"), { desc = "Start incremental selection" })
      vim.keymap.set("x", "grn", ts_select("parent"), { desc = "Increment selection" })
      vim.keymap.set("x", "grc", ts_select("child"), { desc = "Shrink selection" })
      vim.keymap.set("x", "gr]", ts_select("next"), { desc = "Next node selection" })
      vim.keymap.set("x", "gr[", ts_select("prev"), { desc = "Previous node selection" })


    '';
  };
}
