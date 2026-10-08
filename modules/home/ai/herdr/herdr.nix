{
  lib,
  inputs,
  pkgs,
  ...
}:
let
  llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # The agent skill herdr ships (https://herdr.dev/docs/agent-skill/): the
  # release-matched copy of skills/herdr/SKILL.md, which `herdr --skill` prints
  # from the installed binary.
  #
  # Derived from that binary rather than copied into this repo or fetched from
  # the release tag: the skill teaches the CLI surface, so it must never drift
  # from the herdr that is actually installed, and this repo already pins herdr
  # (llm-agents). A flake input of github:herdrdev/herdr would be a second
  # version pin to keep in step; a fetchurl on v${version} would need its hash
  # bumped on every herdr update.
  herdrSkill = pkgs.runCommand "herdr-agent-skill" { } ''
    mkdir -p $out
    ${llmAgents.herdr}/bin/herdr --skill > $out/SKILL.md
  '';
in
{
  # The kanban board plugin. It lives in its own repo (adace123/herdr-kanban,
  # pinned as a flake input) because the Nix packaging is *about the plugin* —
  # it enumerates the plugin's modules and asserts nothing ships unimported —
  # so it belongs next to the code it guards, where that repo's CI can run it.
  #
  # The plugin's home-manager module owns the deployment: the packaged app and
  # launcher, the copied plugin directory
  # (~/.config/herdr/plugins-managed/kanban), the config, `herdr plugin link`,
  # and restarting the background reconciler. It also puts the `herdr-kanban`
  # CLI (`--snapshot`, `--selftest`, or the board itself outside herdr) on
  # PATH. What stays here is what is ours: the keybindings below, and
  # kanban-config.toml with our workspace codes and model names.
  imports = [ inputs.herdr-kanban.homeModules.default ];

  programs.herdr-kanban = {
    enable = true;
    config = ./kanban-config.toml;
  };

  home.packages = [
    llmAgents.herdr
  ];

  # herdr's pi integration reports the pane's agent lifecycle, but it cannot see
  # that `ask_user_question` has stopped the turn to wait on you: the tool runs
  # inside the turn, so the pane keeps reporting `working` and everything that
  # reads herdr — the sidebar, the kanban board's Blocked column — sees a busy
  # agent. This sibling extension translates the questionnaire's own
  # `rpiv:ask-user:blocked` event onto herdr's `herdr:blocked` channel, which is
  # the one the integration consumes (pi-subagents uses it the same way for a
  # run that needs attention), so a waiting pane reads Blocked and reads Working
  # again the moment you answer.
  #
  # A sibling rather than a patch: `herdr-agent-state.ts` is herdr-managed and
  # replaced by `herdr integration install pi`, and its header says to add
  # custom hooks beside it. See modules/home/ai/herdr/pi-extensions/.
  home.file.".pi/agent/extensions/herdr-ask-blocked.ts".source = ./pi-extensions/herdr-ask-blocked.ts;

  # ...and, beside it, the skill that teaches an agent to drive herdr. Declared
  # here rather than in pi.nix/claude.nix because herdr owns the file: both
  # harnesses get the same derivation output, so pi (~/.pi/agent/skills/ is
  # auto-discovered) and Claude Code read the same bytes as the binary that
  # serves the pane they run in.
  home.file.".pi/agent/skills/herdr" = {
    source = herdrSkill;
    recursive = true;
  };

  programs.claude-code.skills.herdr = herdrSkill;

  # herdr plugins (both .sh plugins, deployed via the activation scripts
  # below): herdr-picker (fuzzy launcher) and herdr-automations
  # (cron-scheduled agent runs).
  #
  # Deployment: because `herdr plugin link` canonicalises the linked path (a
  # store symlink would go stale on every rebuild), the activation script below
  # copies the two plugin files into a stable, real directory
  # (~/.config/herdr/plugins-managed/picker) and links that path once.
  xdg.configFile."herdr/config.toml".text = ''
    onboarding = false

    [theme]
    name = "catppuccin"
    auto_switch = false

    [ui] 
    toast.delivery = "system"

    [keys]
    focus_pane_left = "ctrl+H"
    focus_pane_right = "ctrl+L"
    focus_pane_up = "ctrl+K"
    focus_pane_down = "ctrl+J"
    split_vertical = "ctrl+V"
    goto = "ctrl+G"
    workspace_picker = "ctrl+P"
    navigate_workspace_up = "k"
    navigate_workspace_down = "j"
    previous_workspace = "ctrl+["
    next_workspace = "ctrl+]"
    previous_agent = "ctrl+{"
    next_agent = "ctrl+}"
    # Prefix-free tab switching. Not ctrl+tab/ctrl+shift+tab: Ghostty's
    # built-in `ctrl+tab=next_tab` keybind consumes those before herdr sees
    # them. Both chords below are unbound in Ghostty, and herdr pushes the
    # Kitty keyboard protocol to the outer terminal, so they arrive as
    # CSI 44;5u / 46;5u rather than being swallowed.
    previous_tab = "ctrl+,"
    next_tab = "ctrl+."

    [[keys.command]]
    key = "prefix+l"
    type = "popup"
    command = "lazygit"
    description = "run lazygit"
    width = "80%"
    height = "80%"

    # herdr-picker plugin — fuzzy-launch spaces / sessions / tabs / worktrees /
    # files / commands / agents / automations.
    #
    # Bound to ctrl+C (prefix-free). Herdr intercepts the chord, so it no longer
    # interrupts whatever runs in the focused pane — that was the picker's
    # original binding, kept deliberately (see docs/ai.md).
    [[keys.command]]
    key = "ctrl+C"
    type = "plugin_action"
    command = "herdr-picker.launch"
    description = "fuzzy-launch (spaces / tabs / worktrees / files / commands / agents)"

    # herdr-kanban plugin — the board overlay.
    [[keys.command]]
    key = "prefix+k"
    type = "plugin_action"
    command = "herdr-kanban.open"
    description = "kanban board"

    # ...and quick capture into it: a centred popup with the add form, seeded
    # from the workspace you are in. Enter saves and closes the popup.
    #
    # A direct terminal-mode chord (no prefix), because capture should be one
    # keystroke. Some terminals collapse ctrl+shift+<letter> into ctrl+<letter>;
    # if this one does nothing, use "prefix+shift+k" instead.
    [[keys.command]]
    key = "ctrl+A"
    type = "plugin_action"
    command = "herdr-kanban.quick-add"
    description = "kanban: capture a task"
  '';

  # herdr-picker — a .sh herdr plugin over eight categories (spaces, sessions,
  # tabs, worktrees, files, commands, agents, automations). Copies the plugin
  # files into a stable, writable directory and registers it with herdr,
  # idempotently (only links when not already present). Same stable-dir +
  # `herdr plugin link` pattern as the plugins below: herdr canonicalises the
  # linked path, so a store symlink would go stale on every rebuild.
  home.activation.herdrPickerPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    pluginDir="$HOME/.config/herdr/plugins-managed/picker"
    mkdir -p "$pluginDir"
    cp -f "${./plugins/picker/herdr-plugin.toml}" "$pluginDir/herdr-plugin.toml"
    cp -f "${./plugins/picker/launcher.sh}" "$pluginDir/launcher.sh"
    chmod +x "$pluginDir/launcher.sh"

    # Repo-managed picker settings -> plugin config dir (real, editable file;
    # a store symlink would be read-only). herdr seeds nothing if this exists.
    pickerCfg="$HOME/.config/herdr/plugins/config/herdr-picker"
    mkdir -p "$pickerCfg"
    cp -f "${./plugins/picker/config.toml}" "$pickerCfg/config.toml"

    herdrBin="$(command -v herdr 2>/dev/null || true)"
    [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
    if [ -x "$herdrBin" ]; then
      if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-picker"; then
        "$herdrBin" plugin link "$pluginDir" >/dev/null 2>&1 || true
      fi
    fi
  '';

  # herdr-automations — a .sh herdr plugin: cron-scheduled automations.
  # Each automation names a cron schedule, workspace, agent, and command;
  # a daemon (spawned by the plugin's [[startup]] hook) fires due ones as
  # visible herdr workspaces. Same stable-dir + `herdr plugin link` pattern
  # as the picker above.
  #
  # Automation TOML files are user data, not repo-managed: activation seeds
  # the example file only when automations/ does not exist yet, and never
  # overwrites afterwards. The daemon picks up edits within a minute.
  home.activation.herdrAutomationsPlugin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    autoDir="$HOME/.config/herdr/plugins-managed/automations"
    mkdir -p "$autoDir"
    cp -f "${./plugins/automations/herdr-plugin.toml}" "$autoDir/herdr-plugin.toml"
    cp -f "${./plugins/automations/automations.sh}" "$autoDir/automations.sh"
    chmod +x "$autoDir/automations.sh"

    autoCfg="$HOME/.config/herdr/plugins/config/herdr-automations/automations"
    if [ ! -d "$autoCfg" ] || [ -z "$(ls -A "$autoCfg" 2>/dev/null)" ]; then
      mkdir -p "$autoCfg"
      cp -f "${./plugins/automations/example-cron.toml}" "$autoCfg/example-cron.toml"
    fi

    herdrBin="$(command -v herdr 2>/dev/null || true)"
    [ -x "$herdrBin" ] || herdrBin="$HOME/.local/bin/herdr"
    if [ -x "$herdrBin" ]; then
      if ! "$herdrBin" plugin list 2>/dev/null | grep -q "herdr-automations"; then
        "$herdrBin" plugin link "$autoDir" >/dev/null 2>&1 || true
      fi
    fi
  '';
}
