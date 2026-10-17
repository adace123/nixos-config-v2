# Beszel hub + agent from upstream release binaries, because the service-logs
# panel (GetSystemdLogs action, hub UI) needs >= 0.21.0 and nixpkgs only has
# 0.20.0. Every host here is aarch64-linux and upstream publishes statically
# linked arm64 binaries, so there is nothing to compile: unpack each tarball
# and rename the hub binary to what the NixOS module expects
# (bin/beszel-hub, bin/beszel-agent).
#
# Revisit when nixpkgs catches up: delete this file and drop the package=
# overrides in flake-parts/nixos.nix and modules/nixos/beszel-agent.nix.
{ pkgs }:
let
  version = "0.21.0";
  hubTarball = pkgs.fetchurl {
    url = "https://github.com/henrygd/beszel/releases/download/v${version}/beszel_linux_arm64.tar.gz";
    hash = "sha256-xXTjUcyHAZTmr6rsNs37wuwjiNp2fy8bVEaS61O4024=";
  };
  agentTarball = pkgs.fetchurl {
    url = "https://github.com/henrygd/beszel/releases/download/v${version}/beszel-agent_linux_arm64.tar.gz";
    hash = "sha256-goBCBaNwp5BnnoNsPD1li8gEIFUX4cP2dtup+tBkreU=";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "beszel";
  inherit version;
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    tar -xzf ${hubTarball} -O beszel > $out/bin/beszel-hub
    tar -xzf ${agentTarball} -O beszel-agent > $out/bin/beszel-agent
    chmod +x $out/bin/beszel-hub $out/bin/beszel-agent
    runHook postInstall
  '';
  meta = {
    description = "Lightweight server monitoring hub with historical data, docker stats, and alerts";
    homepage = "https://github.com/henrygd/beszel";
    license = pkgs.lib.licenses.mit;
    platforms = [ "aarch64-linux" ];
  };
}
