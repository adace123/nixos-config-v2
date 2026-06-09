# Minimal Raspberry Pi 4 boot config — no nixos-raspberrypi dependency
{ lib, pkgs, ... }:

let
  uboot = pkgs.ubootRaspberryPi4_64bit;
  fw = pkgs.raspberrypifw;
in
{
  # Use stock kernel from cache.nixos.org
  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;

  # Disable GRUB — using U-Boot + extlinux
  boot.loader.grub.enable = false;

  # U-Boot + extlinux for multi-generation boot
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.kernelParams = [
    "console=serial0,115200n8"
    "console=tty1"
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "vc4"
    "pcie_brcmstb"
    "reset-raspberrypi"
  ];

  hardware.enableRedistributableFirmware = true;

  # Populate /boot with RPi boot files after each rebuild
  system.activationScripts.rpi-boot = lib.mkAfter ''
        mkdir -p /boot/broadcom

        # U-Boot bootloader
        cp ${uboot}/u-boot.bin /boot/u-boot.bin

        # Device tree blobs
        cp ${fw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb /boot/broadcom/

        # RPi GPU firmware config
        cat > /boot/config.txt << 'BOOTCFG'
    arm_64bit=1
    enable_uart=1
    avoid_warnings=1
    kernel=u-boot.bin
    gpu_mem=64
    initramfs initrd followkernel
    BOOTCFG
  '';

  environment.systemPackages = [ fw ];
}
