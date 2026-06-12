{ inputs, ... }: {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda"; # USB SSD — verify with `lsblk`
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
}
