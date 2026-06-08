{ ... }:
{
  imports = [
    ./base.nix
  ];

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
}
