{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
{
  imports = [
    ./base.nix
    inputs.disko.nixosModules.disko
  ];

  _module.args.diskoDevice = lib.mkDefault "/dev/sda";

  disko.devices.disk.main = {
    type = "disk";
    device = config._module.args.diskoDevice;
    content = {
      type = "gpt";
      partitions = {
        firmware = {
          size = "1024M";
          type = "0700"; # plain MS basic data, NOT EF00
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/firmware";
            mountOptions = [
              "noatime"
              "umask=0022"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  # Use stock mainline kernel from cache.nixos.org instead of vendor RPi kernel
  # (avoids 30+ min source build — vendor kernel not in binary cache)
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;
  boot.loader.raspberry-pi = {
    bootloader = "kernel";
    configurationLimit = 2;
  };
  boot.initrd.availableKernelModules = [
    "uas"
    "usb_storage"
    "sd_mod"
    "scsi_mod"
  ];
  boot.kernelParams = [ "rootwait" ];

  fileSystems."/boot/firmware".neededForBoot = true;
  systemd.tmpfiles.rules = [ "d /boot/firmware 0755 root root -" ];
}
