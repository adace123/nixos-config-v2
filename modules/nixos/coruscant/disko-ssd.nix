{ inputs, ... }: {
  imports = [ inputs.disko.nixosModules.disko ];

  disko.devices.disk.main = {
    type = "disk";
    # Consider replacing with a stable path like: /dev/disk/by-id/usb-SSDO_Device_...
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        firmware = {
          size = "500M";
          type = "0700";
          attributes = [ 0 ];
          content = {
            type = "filesystem";
            format = "vfat";
            label = "FIRMWARE";
            mountpoint = "/boot/firmware";
            mountOptions = [
              "noatime"
            ];
          };
        };
        esp = {
          size = "500M";
          type = "EF00";
          attributes = [ 2 ];
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
