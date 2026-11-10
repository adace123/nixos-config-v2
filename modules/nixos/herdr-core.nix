{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  llmAgents = inputs.llm-agents.packages.${system};
  herdrCore = llmAgents.herdr-core;
in
# Herdr core: the runtime the Herdr app and the Herdr mobile app talk to.
#
# The phone needs nothing served from this host — it connects over SSH and drives
# the core directly (`hc connect`), so there is no bridge, port or vhost here.
# What it does need is a core that stays running and an `hc` on the login shell's
# PATH (systemPackages provides it through /run/current-system/sw/bin).
#
# Everything is per-user, hence linger: without it the user manager stops at
# logout and takes the core (and every terminal in it) with it. The phone must
# connect as this same user — that is the account whose core it is.
{
  environment.systemPackages = [
    herdrCore
    # Agents work on checkouts of real repositories, so the host needs git and a
    # way to move files off it. curl/rsync are already in the base system; git
    # is not, and `hc run --cwd <repo>` has nothing to operate on without it.
    pkgs.git
    # The harnesses the phone's Inbox shows. Agents report through OSC 7501;
    # omp comes from llm-agents prebuilt on purpose, because the repo's own `omp`
    # flake input builds `omp-native` with bun, which OOMed this 2 OCPU / 12 GB
    # guest twice (2026-11-08) and needed an OCI reset each time.
    llmAgents.claude-code
    llmAgents.omp
  ];

  users.users.nixos.linger = true;

  # `hc server start` returns once the core is up, so a oneshot with
  # RemainAfterExit is the right shape. ExecStop parks the core.
  systemd.user.services.herdr-core = {
    description = "herdr-core: terminals that keep running";
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${herdrCore}/bin/hc server start";
      ExecStop = "${herdrCore}/bin/hc server stop";
    };
  };
}
