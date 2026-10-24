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
    ./rpi-boot.nix
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

  boot.initrd.availableKernelModules = [
    "uas"
    "usb_storage"
    "sd_mod"
    "scsi_mod"
  ];

  systemd.tmpfiles.rules = [ "d /boot/firmware 0755 root root -" ];

  # SMART monitoring for the boot SSD. The drive hangs off a USB-SATA
  # bridge (see the uas/usb_storage initrd modules above), so smartd
  # needs the SAT translation layer (-d sat). Short self-test daily,
  # long self-test weekly; results and failures land in the journal.
  # Verify after switching: smartctl -d sat -H /dev/sda (if the bridge
  # rejects SAT, -d auto is the fallback).
  environment.systemPackages = [ pkgs.smartmontools ];
  services.smartd = {
    enable = true;
    autodetect = false;
    devices = [
      {
        device = "/dev/sda";
        options = "-d sat -a -S on -o on -s (S/../.././02|L/../../7/04)";
      }
    ];
  };
}
