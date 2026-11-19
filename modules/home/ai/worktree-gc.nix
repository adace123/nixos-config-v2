{
  config,
  pkgs,
  ...
}:

# Daily sweep of agent worktrees whose branch has landed. Agent sessions end
# when they open a merge request, before it merges, so the "remove after merge"
# step in the git-worktrees rule (claude.nix) never runs on its own. See
# git-worktree-gc.sh for exactly what is removed and what is kept.
let
  git-worktree-gc = pkgs.writeShellApplication {
    name = "git-worktree-gc";
    runtimeInputs = with pkgs; [
      git
      findutils
      coreutils
    ];
    # The script carries its own shebang and `set -euo pipefail`.
    text = builtins.readFile ./git-worktree-gc.sh;
  };
  logFile = "${config.home.homeDirectory}/Library/Logs/git-worktree-gc.log";
in
{
  # On PATH too, for `git-worktree-gc --dry-run` by hand.
  home.packages = [ git-worktree-gc ];

  # No fetch in the job: an SSH fetch from launchd would raise 1Password agent
  # prompts. Ordinary fetches keep origin current, and fetch.prune (git.nix)
  # marks merged-and-deleted branches as gone.
  launchd.agents.git-worktree-gc = {
    enable = true;
    config = {
      ProgramArguments = [ "${git-worktree-gc}/bin/git-worktree-gc" ];
      # launchd runs a missed calendar slot on wake, so a closed lid at 10:00
      # only delays the sweep.
      StartCalendarInterval = [
        {
          Hour = 10;
          Minute = 0;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };
}
