{
  lib,
  ...
}:
{
  imports = [
    ./base.nix
    ./rpi-boot.nix
  ];

  # Root on the SD card — the sd-image module partitions the card as
  # /boot/firmware (vfat) + root (ext4, labeled NIXOS_SD); declare the same
  # layout here so the non-image config evaluates and remote rebuilds work.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
  fileSystems."/boot/firmware" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = [
      "noatime"
      "noauto"
      "x-systemd.automount"
      "x-systemd.idle-timeout=1min"
    ];
  };

  # The sd-image module pulls in all-hardware, which enables ZFS; zfs-kernel is
  # broken for the latest kernel and ZFS is unused on SD boot. This mirrors the
  # 'sd-image-aarch64-new-kernel-no-zfs-installer' pattern from nixpkgs.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  boot.initrd.availableKernelModules = [
    "mmc_block"
    "sd_mod"
  ];
}
