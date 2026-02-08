{pkgs, ...}: {
  # Extra Lua configuration
  programs.nvf.settings.vim.luaConfigRC = {
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

    claude-terminal = ''
      local Terminal = require("toggleterm.terminal").Terminal
      local claude_term = Terminal:new({
        cmd = "claude",
        direction = "float",
        float_opts = { border = "curved" },
        close_on_exit = true,
        on_open = function(term)
          vim.cmd("startinsert")
        end,
      })
      vim.keymap.set({"n", "t"}, "<leader>ac", function()
        claude_term:toggle()
      end, { desc = "Toggle Claude" })

      local gemini_term = Terminal:new({
        cmd = "bunx -y @google/gemini-cli",
        direction = "float",
        float_opts = { border = "curved" },
        close_on_exit = true,
        on_open = function(term)
          vim.cmd("startinsert")
        end,
      })
      vim.keymap.set({"n", "t"}, "<leader>ag", function()
        gemini_term:toggle()
      end, { desc = "Toggle Gemini" })

      local copilot_term = Terminal:new({
        cmd = "bunx -y @github/copilot",
        direction = "float",
        float_opts = { border = "curved" },
        close_on_exit = true,
        on_open = function(term)
          vim.cmd("startinsert")
        end,
      })
      vim.keymap.set({"n", "t"}, "<leader>ap", function()
        copilot_term:toggle()
      end, { desc = "Toggle Copilot" })
    '';

    toggleterm-insert-mode = ''
      -- Always enter insert mode when opening or entering a terminal
      vim.api.nvim_create_autocmd({"TermOpen", "BufEnter"}, {
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

    auto-reload = ''
      -- Auto-reload files when they change on disk
      vim.api.nvim_create_autocmd({'FocusGained', 'BufEnter', 'CursorHold', 'CursorHoldI'}, {
        pattern = '*',
        callback = function()
          if vim.fn.mode() ~= 'c' then
            vim.cmd('checktime')
          end
        end,
      })

      -- Notification when file changes
      vim.api.nvim_create_autocmd('FileChangedShellPost', {
        pattern = '*',
        callback = function()
          vim.notify('File changed on disk. Buffer reloaded.', vim.log.levels.WARN)
        end,
      })
    '';

    telescope-buffer-delete = ''
      -- Configure telescope to delete buffer with ctrl+d
      local telescope = require('telescope')
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      -- Custom action to delete buffer
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
    '';
  };
}
