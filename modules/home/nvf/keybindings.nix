{pkgs, ...}: {
  # Keybindings
  programs.nvf.settings.vim.maps = {
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
      "<leader>Q" = {
        action = "<cmd>q<cr>";
        desc = "Quit";
      };
      "<Esc>" = {
        action = "<cmd>nohlsearch<cr>";
      };
      "X" = {
        action = "<cmd>bp|bd #<cr>";
        desc = "Delete buffer (keep window)";
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
        desc = "Scroll down and center";
      };
      "<C-u>" = {
        action = "<C-u>zz";
        desc = "Scroll up and center";
      };

      # Toggle terminal
      "<C-a>" = {
        action = "<cmd>ToggleTerm direction=float<cr>";
        desc = "Toggle floating terminal";
      };
      "<C-f>" = {
        action = "<cmd>ToggleTerm direction=float<cr>";
        desc = "Toggle floating terminal";
      };

      # Window navigation
      "<C-h>" = {
        action = "<C-w>h";
        desc = "Move to left window";
      };
      "<C-j>" = {
        action = "<C-w>j";
        desc = "Move to below window";
      };
      "<C-k>" = {
        action = "<C-w>k";
        desc = "Move to above window";
      };
      "<C-l>" = {
        action = "<C-w>l";
        desc = "Move to right window";
      };
      "<C-x>" = {
        action = "<cmd>close<cr>";
        desc = "Close window";
      };

      # Resize windows
      "<C-Up>" = {
        action = "<cmd>resize +2<cr>";
        desc = "Increase window height";
      };
      "<C-Down>" = {
        action = "<cmd>resize -2<cr>";
        desc = "Decrease window height";
      };
      "<C-Left>" = {
        action = "<cmd>vertical resize -2<cr>";
        desc = "Decrease window width";
      };
      "<C-Right>" = {
        action = "<cmd>vertical resize +2<cr>";
        desc = "Increase window width";
      };

      # Buffer navigation
      "<S-h>" = {
        action = "<cmd>bnext<cr>";
        desc = "Next buffer";
      };
      "<S-l>" = {
        action = "<cmd>bprevious<cr>";
        desc = "Previous buffer";
      };
      "<leader>bd" = {
        action = "<cmd>bdelete<cr>";
        desc = "Delete buffer";
      };

      # Move lines
      "<A-j>" = {
        action = "<cmd>m .+1<cr>==";
        desc = "Move line down";
      };
      "<A-k>" = {
        action = "<cmd>m .-2<cr>==";
        desc = "Move line up";
      };

      # Neo-tree
      "<leader>e" = {
        action = "<cmd>Neotree toggle<cr>";
        desc = "Toggle Neo-tree";
      };

      # Yazi
      "-" = {
        action = "<cmd>Yazi<cr>";
        desc = "Open Yazi";
      };

      # Telescope
      "<leader>ff" = {
        action = "<cmd>Telescope find_files<cr>";
        desc = "Find files";
      };
      "<leader>fg" = {
        action = "<cmd>Telescope live_grep<cr>";
        desc = "Live grep";
      };
      "<leader>fw" = {
        action = "<cmd>Telescope live_grep<cr>";
        desc = "Live grep";
      };
      "<leader>fb" = {
        action = "<cmd>Telescope buffers<cr>";
        desc = "Buffers";
      };
      "<leader>fh" = {
        action = "<cmd>Telescope help_tags<cr>";
        desc = "Help tags";
      };
      "<leader>fr" = {
        action = "<cmd>Telescope oldfiles<cr>";
        desc = "Recent files";
      };
      "<leader>fd" = {
        action = "<cmd>Telescope diagnostics<cr>";
        desc = "Diagnostics";
      };
      "<leader>w" = {
        action = "<cmd>Telescope live_grep<cr>";
        desc = "Live grep";
      };
      "<leader>." = {
        action = "<cmd>Telescope resume<cr>";
        desc = "Resume last search";
      };

      "B" = {
        action = "<cmd>Telescope buffers<cr>";
        desc = "Select buffer";
      };

      # UI
      "<leader>ut" = {
        action = "<cmd>Telescope colorscheme<cr>";
        desc = "Pick colorscheme";
      };

      # Splits
      "<leader>sv" = {
        action = "<cmd>vsplit<cr>";
        desc = "Vertical split";
      };
      "<leader>sh" = {
        action = "<cmd>split<cr>";
        desc = "Horizontal split";
      };

      # Markdown
      "<leader>mt" = {
        action = "<cmd>Markview toggle<cr>";
        desc = "Toggle Markview";
      };

      # Terminal
      "<leader>tf" = {
        action = "<cmd>ToggleTerm direction=float<cr>";
        desc = "Float terminal";
      };
      "<leader>th" = {
        action = "<cmd>ToggleTerm direction=horizontal<cr>";
        desc = "Horizontal terminal";
      };
      "<leader>tv" = {
        action = "<cmd>ToggleTerm direction=vertical<cr>";
        desc = "Vertical terminal";
      };
      "<leader>tn" = {
        action = "<cmd>tabnew<cr><cmd>tcd %:p:h<cr>";
        desc = "New tab in current file dir";
      };
      "<leader>ft" = {
        action = "<cmd>Telescope telescope-tabs list_tabs<cr>";
        desc = "Pick tab";
      };

      # Tab cycling
      "<C-]>" = {
        action = "<cmd>tabnext<cr>";
        desc = "Next tab";
      };
      "<C-[>" = {
        action = "<cmd>tabprevious<cr>";
        desc = "Previous tab";
      };
      "<leader>tr" = {
        action = ":Tabby rename_tab ";
        desc = "Rename tab";
      };

      # Set tab working directory
      "<leader>cd" = {
        action = "<cmd>lua vim.ui.input({ prompt = 'Set tab dir: ', completion = 'dir' }, function(dir) if dir then vim.cmd('tcd ' .. dir) end end)<cr>";
        desc = "Set tab working directory";
      };

      # Git
      "<leader>gg" = {
        action = "<cmd>LazyGit<cr>";
        desc = "LazyGit";
      };
      "<leader>gb" = {
        action = "<cmd>Gitsigns blame_line<cr>";
        desc = "Blame line";
      };
      "<leader>gp" = {
        action = "<cmd>Gitsigns preview_hunk<cr>";
        desc = "Preview hunk";
      };
      "<leader>gr" = {
        action = "<cmd>Gitsigns reset_hunk<cr>";
        desc = "Reset hunk";
      };
      "<leader>gS" = {
        action = "<cmd>Gitsigns stage_buffer<cr>";
        desc = "Stage buffer";
      };
      "<leader>gs" = {
        action = "<cmd>Gitsigns stage_hunk<cr>";
        desc = "Stage hunk";
      };
      "<leader>gR" = {
        action = "<cmd>Gitsigns reset_buffer<cr>";
        desc = "Reset buffer";
      };
      "<leader>gu" = {
        action = "<cmd>Gitsigns undo_stage_hunk<cr>";
        desc = "Undo stage hunk";
      };
      "<leader>gU" = {
        action = "<cmd>Gitsigns reset_buffer_index<cr>";
        desc = "Reset buffer index";
      };
      "<leader>gd" = {
        action = "<cmd>Gitsigns diffthis<cr>";
        desc = "Diff this";
      };
      "<leader>gtb" = {
        action = "<cmd>Gitsigns toggle_current_line_blame<cr>";
        desc = "Toggle line blame";
      };
      "<leader>gtd" = {
        action = "<cmd>Gitsigns toggle_deleted<cr>";
        desc = "Toggle deleted";
      };
      "}" = {
        action = "<cmd>Gitsigns next_hunk<cr>";
        desc = "Next hunk";
      };
      "{" = {
        action = "<cmd>Gitsigns prev_hunk<cr>";
        desc = "Previous hunk";
      };

      # Flash navigation
      "s" = {
        action = "<cmd>lua require('flash').jump()<cr>";
        desc = "Flash jump";
      };
      "S" = {
        action = "<cmd>lua require('flash').treesitter()<cr>";
        desc = "Flash treesitter";
      };
    };

    visual = {
      # Flash navigation
      "s" = {
        action = "<cmd>lua require('flash').jump()<cr>";
        desc = "Flash jump";
      };
      "S" = {
        action = "<cmd>lua require('flash').treesitter()<cr>";
        desc = "Flash treesitter";
      };
      # Move selection
      "<A-j>" = {
        action = ":m '>+1<cr>gv=gv";
        desc = "Move selection down";
      };
      "<A-k>" = {
        action = ":m '<-2<cr>gv=gv";
        desc = "Move selection up";
      };

      # Indent
      "<" = {
        action = "<gv";
        desc = "Indent left and reselect";
      };
      ">" = {
        action = ">gv";
        desc = "Indent right and reselect";
      };

      # Git - stage/reset selection
      "<leader>gs" = {
        action = "<cmd>Gitsigns stage_hunk<cr>";
        desc = "Stage selection";
      };
      "<leader>gr" = {
        action = "<cmd>Gitsigns reset_hunk<cr>";
        desc = "Reset selection";
      };
    };

    terminal = {
      # Toggle terminal in terminal mode
      "<C-a>" = {
        action = "<C-\\><C-n><cmd>ToggleTerm<cr>";
        desc = "Toggle terminal";
      };
      "<C-f>" = {
        action = "<C-\\><C-n><cmd>ToggleTerm<cr>";
        desc = "Toggle terminal";
      };
    };
  };
}
