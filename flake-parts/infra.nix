{ ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.infra = pkgs.mkShell {
        name = "infra";
        packages = with pkgs; [
          just
          opentofu
          sops
          age
        ];
        shellHook = ''
          echo "Infra shell — tools for OCI image builds and OpenTofu"
        '';
      };
    };
}
