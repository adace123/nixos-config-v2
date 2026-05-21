_: {
  programs.zed-editor.userKeymaps = [
    {
      bindings = {
        "ctrl-p" = "projects::OpenRecent";
        "ctrl-s" = "workspace::Save";
        "ctrl-\\" = "terminal_panel::ToggleFocus";
      };
    }

    {
      context = "Dock || Terminal || Editor";
      bindings = {
        "ctrl-/" = "workspace::ToggleBottomDock";
        "ctrl-x" = "pane::CloseAllItems";
        "cmd-shift-s" = "project_panel::NewSearchInDirectory";
        "cmd-shift-g" = "git_panel::Toggle";
        "cmd-p" = "file_finder::Toggle";
      };
    }

    {
      context = "Terminal";
      bindings = {
        "cmd-t" = "workspace::NewTerminal";
      };
    }

    {
      context = "Dock || Terminal || Editor";
      bindings = {
        "ctrl-h" = [
          "workspace::ActivatePaneInDirection"
          "Left"
        ];
        "ctrl-l" = [
          "workspace::ActivatePaneInDirection"
          "Right"
        ];
        "ctrl-k" = [
          "workspace::ActivatePaneInDirection"
          "Up"
        ];
        "ctrl-j" = [
          "workspace::ActivatePaneInDirection"
          "Down"
        ];
      };
    }

    {
      context = "GitPanel";
      bindings = {
        "q" = "git_panel::Close";
        "alt-p" = "git::Push";
      };
    }

    {
      context = "AgentPanel";
      bindings = {
        "ctrl-\\" = "workspace::ToggleRightDock";
        "cmd-k" = "workspace::ToggleRightDock";
      };
    }

    {
      context = "ProjectPanel && not_editing";
      bindings = {
        "a" = "project_panel::NewFile";
        "A" = "project_panel::NewDirectory";
        "r" = "project_panel::Rename";
        "d" = "project_panel::Delete";
        "x" = "project_panel::Cut";
        "c" = "project_panel::Copy";
        "p" = "project_panel::Paste";
        "q" = "workspace::ToggleLeftDock";
        "space e" = "workspace::ToggleLeftDock";
        ":" = "command_palette::Toggle";
        "%" = "project_panel::NewFile";
        "/" = "project_panel::NewSearchInDirectory";
        "o" = "project_panel::OpenPermanent";
        "escape" = "project_panel::ToggleFocus";
        "h" = "project_panel::CollapseSelectedEntry";
        "j" = "menu::SelectNext";
        "k" = "menu::SelectPrevious";
        "l" = "project_panel::ExpandSelectedEntry";
        "enter" = "project_panel::OpenPermanent";
        "t" = "project_panel::OpenPermanent";
        "v" = "project_panel::OpenPermanent";
        "shift-d" = "project_panel::Delete";
        "shift-r" = "project_panel::Rename";
        "shift-g" = "menu::SelectLast";
        "g g" = "menu::SelectFirst";
        "-" = "project_panel::SelectParent";
        "ctrl-6" = "pane::AlternateFile";
      };
    }

    {
      context = "EmptyPane || SharedScreen";
      bindings = {
        "space space" = "file_finder::Toggle";
        "space f n" = "workspace::NewFile";
        "space f p" = "projects::OpenRecent";
        "space s g" = "workspace::NewSearch";
        "space q q" = "zed::Quit";
        "ctrl-p" = "projects::OpenRecent";
      };
    }

    {
      context = "Editor && VimControl && !VimWaiting && !menu";
      bindings = {
        "U" = "editor::Redo";

        "enter" = "editor::SelectLargerSyntaxNode";

        "shift-h" = "pane::ActivatePreviousItem";
        "shift-l" = "pane::ActivateNextItem";

        "space c r" = "editor::Rename";

        "space a a" = "assistant::ToggleFocus";
        "space a c" = "agent::ToggleFocus";
        "ctrl-\\" = "workspace::ToggleRightDock";
        "cmd-k" = "workspace::ToggleRightDock";
        "space a e" = "assistant::InlineAssist";
        "cmd-l" = "assistant::InlineAssist";
        "space a t" = "workspace::ToggleRightDock";

        "shift-f" = "pane::DeploySearch";

        "space f f" = "file_finder::Toggle";

        "space k s" = [
          "task::Spawn"
          {
            "task_name" = "k9s";
            "reveal_target" = "center";
          }
        ];

        "space g g" = [
          "task::Spawn"
          {
            "task_name" = "lazygit";
            "reveal_target" = "center";
          }
        ];
        "space g r" = "git::Restore";
        "space g s" = "git::ToggleStaged";
        "space g S" = "git::StageAll";
        "space g h d" = "editor::ExpandAllDiffHunks";
        "space g d" = "git::Diff";
        "space g h r" = "git::Restore";
        "space g h R" = "git::RestoreFile";
        "space g l" = "git::Blame";

        "space u i" = "editor::ToggleInlayHints";
        "space u w" = "editor::ToggleSoftWrap";

        "space m p" = "markdown::OpenPreview";
        "space m P" = "markdown::OpenPreviewToTheSide";

        "space f p" = "projects::OpenRecent";

        "space s w" = "buffer_search::Deploy";
        "space o" = "outline::Toggle";
        "space s W" = "pane::DeploySearch";
        "space w" = "workspace::NewSearch";
        "space /" = "editor::ToggleComments";
        "space s b" = "vim::Search";

        "space 1" = [
          "pane::ActivateItem"
          0
        ];
        "space 2" = [
          "pane::ActivateItem"
          1
        ];
        "space 3" = [
          "pane::ActivateItem"
          2
        ];
        "space 4" = [
          "pane::ActivateItem"
          3
        ];
        "space 5" = [
          "pane::ActivateItem"
          4
        ];
        "space 6" = [
          "pane::ActivateItem"
          5
        ];
        "space 7" = [
          "pane::ActivateItem"
          6
        ];
        "space 8" = [
          "pane::ActivateItem"
          7
        ];
        "space 9" = [
          "pane::ActivateItem"
          8
        ];
        "space 0" = "pane::ActivateLastItem";
        "] b" = "pane::ActivateNextItem";
        "[ b" = "pane::ActivatePreviousItem";
        "space ," = "tab_switcher::Toggle";

        "space b b" = "pane::AlternateFile";
        "space b d" = "pane::CloseActiveItem";
        "space b q" = "pane::CloseInactiveItems";
        "space b n" = "workspace::NewFile";
        "shift-x" = "pane::CloseActiveItem";
        "space Y" = [
          "workspace::SendKeystrokes"
          "cmd-a cmd-c esc"
        ];

        "space space" = "file_finder::Toggle";
        "space f n" = "workspace::NewFile";

        "space e" = "workspace::ToggleLeftDock";

        "space t" = "task::Spawn";

        "space s v" = "pane::SplitRight";
        "space s s" = "pane::SplitDown";
        "space -" = "pane::SplitDown";
        "space |" = "pane::SplitRight";
        "space `" = "workspace::NewCenterTerminal";

        "space c a" = "editor::ToggleCodeActions";
        "space s d" = "diagnostics::Deploy";
        "space s o" = "outline::Toggle";
        "space c f" = "editor::Format";

        "] h" = "editor::GoToHunk";
        "[ h" = "editor::GoToPreviousHunk";
        "]" = "editor::GoToHunk";
        "[" = "editor::GoToPreviousHunk";
        "}" = "editor::GoToHunk";
        "{" = "editor::GoToPreviousHunk";
        "] c" = "editor::GoToHunk";
        "[ c" = "editor::GoToPreviousHunk";

        "] d" = "editor::GoToDiagnostic";
        "[ d" = "editor::GoToPreviousDiagnostic";
        "] e" = "editor::GoToDiagnostic";
        "[ e" = "editor::GoToPreviousDiagnostic";

        "] q" = "editor::MoveToStartOfNextExcerpt";
        "[ q" = "editor::MoveToStartOfExcerpt";

        "space q q" = "zed::Quit";

        "g r" = "editor::FindAllReferences";
      };
    }

    {
      context = "Editor && vim_mode == visual && !VimWaiting && !VimObject";
      bindings = {
        "shift-j" = "editor::MoveLineDown";
        "shift-k" = "editor::MoveLineUp";
      };
    }

    {
      context = "Editor && vim_mode == insert && !VimWaiting";
      bindings = {
        "j k" = "vim::NormalBefore";
        "k j" = "vim::NormalBefore";
      };
    }

    {
      context = "VimControl && !menu";
      bindings = {
        "ctrl-d" = [
          "workspace::SendKeystrokes"
          "ctrl-d z z"
        ];
        "ctrl-u" = [
          "workspace::SendKeystrokes"
          "ctrl-u z z"
        ];
        "n" = [
          "workspace::SendKeystrokes"
          "n z z z v"
        ];
        "shift-n" = [
          "workspace::SendKeystrokes"
          "shift-n z z z v"
        ];
        "shift-g" = [
          "workspace::SendKeystrokes"
          "shift-g z z"
        ];
      };
    }

    {
      context = "vim_operator == d";
      bindings = {
        "o" = "editor::ExpandAllDiffHunks";
        "r" = "git::Restore";
      };
    }

    {
      context = "vim_mode == normal || vim_mode == visual";
      bindings = {
        "s" = "vim::PushSneak";
        "S" = "vim::PushSneakBackward";
      };
    }

    {
      context = "vim_operator == a || vim_operator == i || vim_operator == cs";
      bindings = {
        "b" = "vim::AnyBrackets";
      };
    }
  ];
}
