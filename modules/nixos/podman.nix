{
  pkgs,
  ...
}:
{
  # Podman — daemonless container engine, drop-in replacement for Docker.
  # Configured for rootful operation with the podman socket exposed, so the
  # Mac (endor) can manage containers remotely via SSH:
  #
  #   podman system connection add coruscant --identity ~/.ssh/<key> ssh://nixos@coruscant/run/podman/podman.sock
  #
  # The nixos user is in the `podman` group, which owns the socket.
  virtualisation.podman = {
    enable = true;
    # docker CLI compatibility (docker -> podman alias + manpages)
    dockerCompat = true;
    # Expose /run/docker.sock as a symlink to /run/podman/podman.sock so
    # docker tools (compose, clients) work against podman
    dockerSocket.enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  environment.systemPackages = with pkgs; [
    podman
    podman-compose
    podman-tui
  ];

  # Rootful podman socket is group-owned by `podman`; grant the nixos user
  # access so SSH-based remote connections work without root.
  users.users.nixos.extraGroups = [ "podman" ];
}
