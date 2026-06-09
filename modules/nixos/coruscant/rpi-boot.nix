# Minimal Raspberry Pi 4 boot config — no nixos-raspberrypi dependency
{ lib, pkgs, ... }:

let
  uboot = pkgs.ubootRaspberryPi4_64bit;
  fw = pkgs.raspberrypifw;
  configTxt = pkgs.writeText "config.txt" ''
    arm_64bit=1
    enable_uart=1
    avoid_warnings=1
    kernel=u-boot.bin
    gpu_mem=64
    initramfs initrd followkernel
  '';
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

  # Copy RPi firmware files to /boot on each activation
  system.activationScripts.rpi-boot = lib.mkAfter ''
    mkdir -p /boot/broadcom
    cp -f ${uboot}/u-boot.bin /boot/u-boot.bin
    cp -f ${configTxt} /boot/config.txt
    cp -f ${fw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb /boot/broadcom/
    cp -f ${fw}/share/raspberrypi/boot/bcm2711-rpi-4-b.dtb /boot/bcm2711-rpi-4-b.dtb
  '';

  environment.systemPackages = [ fw ];
}
