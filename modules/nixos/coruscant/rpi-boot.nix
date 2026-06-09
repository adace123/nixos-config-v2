# Minimal Raspberry Pi 4 boot config — no nixos-raspberrypi dependency
# Firmware files (config.txt, u-boot.bin, DTBs, GPU firmware) are populated
# on the boot partition by disko-ssd.nix's postCreateHook during disk setup.
{ lib, pkgs, ... }:

{
  boot = {
    # Use stock kernel from cache.nixos.org
    kernelPackages = lib.mkForce pkgs.linuxPackages;

    # U-Boot + extlinux for multi-generation boot
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;

    kernelParams = [
      "console=serial0,115200n8"
      "console=tty1"
    ];

    initrd.availableKernelModules = [
      "xhci_pci"
      "usbhid"
      "usb_storage"
      "vc4"
      "pcie_brcmstb"
      "reset-raspberrypi"
    ];
  };

  hardware.enableRedistributableFirmware = true;

  # Device tree for RPi 4
  hardware.deviceTree = {
    enable = true;
    filter = "*rpi-4*.dtb";
  };
}
