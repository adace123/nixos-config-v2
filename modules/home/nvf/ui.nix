_: {
  programs.nvf.settings.vim = {
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
        setupOpts = {
          indent = {
            char = "│";
            tab_char = "│";
          };
          scope = {
            enabled = true;
            show_start = true;
            show_end = true;
          };
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
        "<leader>q" = "+Session";
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
  };
}
