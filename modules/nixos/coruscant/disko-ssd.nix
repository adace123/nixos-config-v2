{ inputs, pkgs, ... }:
let
  uboot = pkgs.ubootRaspberryPi4_64bit;
  fw = pkgs.raspberrypifw;
  armstubs = pkgs.raspberrypi-armstubs;
  configTxt = pkgs.writeText "config.txt" ''
    [pi4]
    kernel=u-boot.bin
    enable_gic=1
    armstub=armstub8-gic.bin

    [all]
    arm_64bit=1
    enable_uart=1
    avoid_warnings=1
  '';
in
{
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "noatime"
              "umask=0077"
            ];
            postCreateHook = ''
              MNTPOINT=$(mktemp -d)
              mount $device $MNTPOINT
              trap 'umount $MNTPOINT; rmdir $MNTPOINT' EXIT

              cp -f ${uboot}/u-boot.bin "$MNTPOINT/u-boot.bin"
              cp -f ${fw}/share/raspberrypi/boot/bootcode.bin "$MNTPOINT/"
              cp -f ${fw}/share/raspberrypi/boot/start4.elf "$MNTPOINT/"
              cp -f ${fw}/share/raspberrypi/boot/fixup4.dat "$MNTPOINT/"
              cp -f ${fw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb "$MNTPOINT/"
              cp -f ${armstubs}/armstub8-gic.bin "$MNTPOINT/"
              cp -f ${configTxt} "$MNTPOINT/config.txt"
            '';
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
}
