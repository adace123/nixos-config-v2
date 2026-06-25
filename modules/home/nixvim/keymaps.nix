{ ... }:
{
  programs.nixvim = {
    # Key mappings
    keymaps = [
      # ── Insert mode ──
      {
        mode = "i";
        key = "jk";
        action = "<Esc>";
        options = {
          desc = "Exit insert mode";
        };
      }
      {
        mode = "i";
        key = "kj";
        action = "<Esc>";
        options = {
          desc = "Exit insert mode";
        };
      }

      # ── Normal mode ──

      # General
      {
        mode = "n";
        key = "<leader>W";
        action = "<cmd>noautocmd w<cr>";
        options = {
          desc = "Save without autocmd";
        };
      }
      {
        mode = "n";
        key = "<C-s>";
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
        key = "<leader>Q";
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
      {
        mode = "n";
        key = "X";
        action = "<cmd>bp|bd #<cr>";
        options = {
          desc = "Delete buffer (keep window)";
        };
      }
      {
        mode = "n";
        key = "U";
        action = "<C-r>";
        options = {
          desc = "Redo";
        };
      }

      # Copy operations
      {
        mode = "n";
        key = "<leader>Y";
        action = "gg\"+yG";
        options = {
          desc = "Copy entire buffer";
        };
      }
      {
        mode = "n";
        key = "yy";
        action = "\"+yy";
        options = {
          desc = "Yank line to clipboard";
        };
      }

      # Scrolling with centering
      {
        mode = "n";
        key = "<C-d>";
        action = "<C-d>zz";
        options = {
          desc = "Scroll down and center";
        };
      }
      {
        mode = "n";
        key = "<C-u>";
        action = "<C-u>zz";
        options = {
          desc = "Scroll up and center";
        };
      }

      # Window navigation
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
      {
        mode = "n";
        key = "<C-x>";
        action = "<cmd>close<cr>";
        options = {
          desc = "Close window";
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

      # Code outline
      {
        mode = "n";
        key = "<leader>o";
        action = "<cmd>lua require('telescope.builtin').lsp_document_symbols({ symbols = { 'class', 'function', 'method', 'constructor', 'interface', 'struct' } })<cr>";
        options = {
          desc = "Telescope code outline";
        };
      }

      # Yazi
      {
        mode = "n";
        key = "-";
        action = "<cmd>Yazi<cr>";
        options = {
          desc = "Open Yazi";
        };
      }

      # Splits
      {
        mode = "n";
        key = "<leader>sv";
        action = "<cmd>vsplit<cr>";
        options = {
          desc = "Vertical split";
        };
      }
      {
        mode = "n";
        key = "<leader>sh";
        action = "<cmd>split<cr>";
        options = {
          desc = "Horizontal split";
        };
      }

      # Terminal
      {
        mode = "n";
        key = "<C-a>";
        action = "<cmd>ToggleTerm direction=float<cr>";
        options = {
          desc = "Toggle floating terminal";
        };
      }
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

      # Markdown
      {
        mode = "n";
        key = "<leader>mt";
        action = "<cmd>Markview toggle<cr>";
        options = {
          desc = "Toggle Markview";
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
      {
        mode = "n";
        key = "<leader>gs";
        action = "<cmd>Gitsigns stage_hunk<cr>";
        options = {
          desc = "Stage hunk";
        };
      }
      {
        mode = "n";
        key = "<leader>gS";
        action = "<cmd>Gitsigns stage_buffer<cr>";
        options = {
          desc = "Stage buffer";
        };
      }
      {
        mode = "n";
        key = "<leader>gR";
        action = "<cmd>Gitsigns reset_buffer<cr>";
        options = {
          desc = "Reset buffer";
        };
      }
      {
        mode = "n";
        key = "<leader>gu";
        action = "<cmd>Gitsigns undo_stage_hunk<cr>";
        options = {
          desc = "Undo stage hunk";
        };
      }
      {
        mode = "n";
        key = "<leader>gU";
        action = "<cmd>Gitsigns reset_buffer_index<cr>";
        options = {
          desc = "Reset buffer index";
        };
      }
      {
        mode = "n";
        key = "<leader>gd";
        action = "<cmd>Gitsigns diffthis<cr>";
        options = {
          desc = "Diff this";
        };
      }
      {
        mode = "n";
        key = "<leader>gtb";
        action = "<cmd>Gitsigns toggle_current_line_blame<cr>";
        options = {
          desc = "Toggle line blame";
        };
      }
      {
        mode = "n";
        key = "<leader>gtd";
        action = "<cmd>Gitsigns toggle_deleted<cr>";
        options = {
          desc = "Toggle deleted";
        };
      }
      {
        mode = "n";
        key = "}";
        action = "<cmd>Gitsigns next_hunk<cr>";
        options = {
          desc = "Next hunk";
        };
      }
      {
        mode = "n";
        key = "{";
        action = "<cmd>Gitsigns prev_hunk<cr>";
        options = {
          desc = "Previous hunk";
        };
      }
      {
        mode = "v";
        key = "<leader>gs";
        action = "<cmd>Gitsigns stage_hunk<cr>";
        options = {
          desc = "Stage selection";
        };
      }
      {
        mode = "v";
        key = "<leader>gr";
        action = "<cmd>Gitsigns reset_hunk<cr>";
        options = {
          desc = "Reset selection";
        };
      }

      # Diagnostics / Trouble
      {
        mode = "n";
        key = "<leader>xx";
        action = "<cmd>Trouble diagnostics toggle<cr>";
        options = {
          desc = "Workspace diagnostics";
        };
      }
      {
        mode = "n";
        key = "<leader>xX";
        action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
        options = {
          desc = "Buffer diagnostics";
        };
      }
      {
        mode = "n";
        key = "<leader>xq";
        action = "<cmd>Trouble qflist toggle<cr>";
        options = {
          desc = "Quickfix list";
        };
      }
      {
        mode = "n";
        key = "<leader>xl";
        action = "<cmd>Trouble loclist toggle<cr>";
        options = {
          desc = "Location list";
        };
      }

      # Flash navigation
      {
        mode = "n";
        key = "s";
        action = "<cmd>lua require('flash').jump()<cr>";
        options = {
          desc = "Flash jump";
        };
      }
      {
        mode = "n";
        key = "S";
        action = "<cmd>lua require('flash').treesitter()<cr>";
        options = {
          desc = "Flash treesitter";
        };
      }
      {
        mode = "v";
        key = "s";
        action = "<cmd>lua require('flash').jump()<cr>";
        options = {
          desc = "Flash jump";
        };
      }
      {
        mode = "v";
        key = "S";
        action = "<cmd>lua require('flash').treesitter()<cr>";
        options = {
          desc = "Flash treesitter";
        };
      }

      # Comments
      {
        mode = "n";
        key = "<leader>/";
        action = "<cmd>lua require('Comment.api').toggle.linewise.current()<cr>";
        options = {
          desc = "Toggle comment";
        };
      }
      {
        mode = "v";
        key = "<leader>/";
        action = "<esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>";
        options = {
          desc = "Toggle comment";
        };
      }

      # Terminal mode: toggle terminal
      {
        mode = "t";
        key = "<C-a>";
        action = "<C-\\><C-n><cmd>ToggleTerm<cr>";
        options = {
          desc = "Toggle terminal";
        };
      }
    ];

  };
}
