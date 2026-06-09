{ inputs, ... }: {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    # Consider replacing with a stable path like: /dev/disk/by-id/usb-SSDO_Device_...
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        # Combined ESP and Firmware
        boot = {
          size = "1G";
          type = "EF00"; # EFI System Partition
          priority = 1; # Forces this to be partition 1
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [
              "noatime"
              "umask=0077"
            ];
          };
        };
        root = {
          size = "100%";
          priority = 2;
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
