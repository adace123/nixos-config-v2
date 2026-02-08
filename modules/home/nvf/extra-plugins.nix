{
  pkgs,
  customPlugins,
  ...
}:
{
  # Extra plugins and configuration
  programs.nvf.settings.vim.extraPlugins = with pkgs.vimPlugins; {
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
    persistence-nvim = {
      package = persistence-nvim;
      setup = ''
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

        -- Auto-restore session on startup
        vim.api.nvim_create_autocmd("VimEnter", {
          nested = true,
          callback = function()
            -- Only restore if no files were opened and not in a suppressed dir
            if vim.fn.argc() == 0 and not should_suppress() then
              require("persistence").load()
            end
          end,
        })

        -- Auto-save session on exit
        vim.api.nvim_create_autocmd("VimLeavePre", {
          callback = function()
            if not should_suppress() then
              require("persistence").save()
            end
          end,
        })

        -- Restore session keybindings
        vim.keymap.set("n", "<leader>qs", function()
          require("persistence").load()
        end, { desc = "Restore session" })

        vim.keymap.set("n", "<leader>ql", function()
          require("persistence").load({ last = true })
        end, { desc = "Restore last session" })

        vim.keymap.set("n", "<leader>qd", function()
          require("persistence").stop()
        end, { desc = "Don't save session" })
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
    tabby-nvim = {
      package = tabby-nvim;
      setup = ''
        local theme = {
          fill = 'TabLineFill',
          head = 'TabLine',
          current_tab = 'TabLineSel',
          tab = 'TabLine',
          win = 'TabLine',
          tail = 'TabLine',
        }
        require('tabby.tabline').set(function(line)
          return {
            {
              { '  ', hl = theme.head },
            },
            line.tabs().foreach(function(tab)
              local hl = tab.is_current() and theme.current_tab or theme.tab
              return {
                line.sep(' ', hl, theme.fill),
                tab.is_current() and '●' or '○',
                ' ',
                tab.name(),
                ' ',
                tab.close_btn('✕'),
                line.sep(' ', hl, theme.fill),
                hl = hl,
                margin = ' ',
              }
            end),
            line.spacer(),
            hl = theme.fill,
          }
        end)
      '';
    };
    telescope-tabs = {
      package = customPlugins.telescope-tabs;
      setup = ''
        require("telescope-tabs").setup({
          entry_formatter = function(tab_id, buffer_ids, file_names, file_paths, is_current)
            -- Get tabby's custom tab name
            local ok, tab_name_module = pcall(require, 'tabby.feature.tab_name')
            local tab_name

            if ok then
              -- Use tabby's get() function to retrieve custom tab name
              tab_name = tab_name_module.get(tab_id)
            end

            -- Fallback to buffer name if no custom name is set
            if not tab_name or tab_name == "" then
              tab_name = file_names[1] or "[No Name]"
            end

            local entry_string = string.format("%d: %s", tab_id, tab_name)
            return entry_string
          end,
        })
      '';
    };
    nvim-treesitter-textobjects = {
      package = nvim-treesitter-textobjects;
      setup = ""; # Configuration is done in luaConfigRC
    };
    yazi-nvim = {
      package = yazi-nvim;
      setup = ''
        require("yazi").setup({})
      '';
    };
  };
}
