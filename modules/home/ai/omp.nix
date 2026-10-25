{ inputs, pkgs, ... }:
{
  imports = [
    inputs.omp.homeManagerModules.default
  ];

  # OMP (oh-my-pi), Nix-managed: package plus ~/.omp/agent/config.yml,
  # written declaratively on every switch (writable regular file, so OMP's
  # runtime rewrites still work and are re-asserted next switch).
  #
  # NOTE: this machine also has a hand-installed brew `omp`
  # (/opt/homebrew/bin/omp). The nix profile bin shadows it once this lands —
  # `brew uninstall omp` removes the spare.
  programs.omp = {
    enable = true;
    # Prebuilt from cache.numtide.com via the llm-agents input (currently
    # 18.12.2 in the lock vs 18.12.6 on upstream main). Upstream's own flake
    # builds from source, which costs a ~15min bun build; the module itself
    # still comes from the omp flake input above.
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;
    settings = {
      hideThinkingBlock = true;
      composer.shape = "band";
      theme.dark = "dark-catppuccin";
      browser.headless = false;
      tools = {
        approvalMode = "always-ask";
        approval.bash = "allow";
      };
      # Transcript noise: `hideToolActivity` keeps tool calls/results out of
      # the transcript (the TUI still shows status rows), which also quiets
      # web_search output. There is no per-tool "hide web_search results"
      # knob — `web_search.enabled = false` is the only way to silence it, and
      # that removes the tool entirely.
      display.hideToolActivity = true;
      modelRoles = {
        # Normal interactive work: strongest cheap Go default (native vision,
        # 1M ctx). Thinking level pins reasoning effort; high is the default.
        default = "opencode-go/glm-5.3-flash:high";
        # Fast, cheap utility work: reads, searches, titles, handoffs. Nothing
        # reasons from its output, so the cheapest bulk model wins.
        smol = "opencode-go/mimo-v2.5";
        # Thorough reasoning where latency is fine: reviewer agent, hard
        # problems. Muse is full-size but lightly served (45k req/5h on Go vs
        # 220 for glm-5.3:max), agentic-tuned, and cross-family from the GLM
        # default. Needs the "paid endpoints that train on request data" opt-in
        # in the OpenCode Console privacy settings.
        slow = "opencode-go/muse-spark-1.3-contributor:high";
        # Passive per-turn review (see `advisor` below): deliberately
        # cross-family from default for independent judgment. Still cheap
        # ($0.10/$0.20, 45k req/5h on Go); low effort because most turns
        # need no note. Raise to :max if notes feel shallow. Caveat: needs
        # the "paid endpoints that train on request data" opt-in in the
        # OpenCode Console privacy settings.
        advisor = "opencode-go/muse-spark-1.3-contributor:low";
      };
      advisor = {
        enabled = true;
      };
    };
  };
}
