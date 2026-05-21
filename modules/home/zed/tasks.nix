{ pkgs, ... }:
{
  programs.zed-editor.userTasks = [
    {
      label = "lazygit";
      command = "${pkgs.lazygit}/bin/lazygit";
      args = [
        "-p"
        "$ZED_WORKTREE_ROOT"
      ];
      use_new_terminal = true;
      allow_concurrent_runs = false;
      reveal = "always";
      hide = "on_success";
    }
    {
      label = "k9s";
      command = "";
      use_new_terminal = true;
      allow_concurrent_runs = false;
      reveal = "always";
      hide = "on_success";
    }
  ];
}
