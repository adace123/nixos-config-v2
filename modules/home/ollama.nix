{
  config,
  ...
}:
{
  # Ollama is a per-user launchd agent on Darwin: home-manager's
  # `services.ollama` defines the launchd job (and the Linux systemd unit) and
  # puts the `ollama` CLI in `home.packages`. The server is bound to localhost,
  # so only this Mac can reach it — Ollama has no authentication, and `0.0.0.0`
  # would hand the LAN unrestricted access to the GPU.
  #
  # Models live in `~/.ollama` (the default). Nothing here manages them; pull
  # them with `ollama pull <model>`.
  #
  # The launchd job is installed at
  # `~/Library/LaunchAgents/org.nix-community.home.ollama.plist` and loaded into
  # the GUI domain, wrapped in `wait4path /nix/store` so it does not race the
  # store mount at login.
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
  };

  # The upstream module sets ProgramArguments, EnvironmentVariables, KeepAlive
  # and ProcessType, but neither RunAtLoad nor the log paths — those merge in
  # through the launchd plist freeform type. KeepAlive alone only restarts the
  # job after a failed exit; RunAtLoad is what starts it at login.
  launchd.agents.ollama.config = {
    RunAtLoad = true;
    StandardOutPath = "${config.home.homeDirectory}/Library/Logs/ollama.log";
    StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/ollama.log";
  };
}
