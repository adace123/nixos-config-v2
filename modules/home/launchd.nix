{
  config,
  lib,
  ...
}:

# home-manager's `setupLaunchAgents` only boots an agent out when its plist is
# already installed in `~/Library/LaunchAgents`. For a job whose label is loaded
# from anywhere else — a manual `launchctl bootstrap` of a store plist while
# developing one, or a job left over from an older experiment — it therefore
# goes straight to `launchctl bootstrap`, which answers `Bootstrap failed: 5:
# Input/output error` and aborts the whole switch. Unload those jobs first so
# every activation bootstraps from the plist home-manager is about to install.
let
  agents = lib.filterAttrs (_: agent: agent.enable) config.launchd.agents;

  # The directory home-manager owns (see its `launchd` module): a job loaded
  # from a file in here is one its own unload path can handle.
  plistDir = "${config.home.homeDirectory}/Library/LaunchAgents";

  # `domain label` per enabled agent. `config.Label` is the option home-manager
  # derives the plist and the `launchctl` job from, so a renamed job is covered
  # too.
  agentTable = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (_: agent: "${agent.domain} ${lib.escapeShellArg agent.config.Label}") agents
  );
in
{
  home.activation.launchdAdoptAgents = lib.mkIf config.launchd.enable (
    lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
      # `launchctl print` reports the plist a job was bootstrapped from; a path
      # outside home-manager's directory is exactly the case its activation
      # cannot recover from. An unloaded job makes `print` fail, so skip it.
      while read -r domain label; do
        domain="$domain/$UID"

        if ! info=$(/bin/launchctl print "$domain/$label" 2>/dev/null); then
          continue
        fi

        loaded=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*path = //p' | head -n 1)
        if [[ -z "$loaded" || "$loaded" == "${plistDir}/$label.plist" ]]; then
          continue
        fi

        warnEcho "Unloading agent '$domain/$label', which is loaded from '$loaded'"
        $DRY_RUN_CMD /bin/launchctl bootout "$domain/$label" \
          || warnEcho "Failed to unload '$domain/$label'"
      done <<'AGENTS'
      ${agentTable}
      AGENTS
    ''
  );
}
