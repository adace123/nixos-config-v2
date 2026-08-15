{
  pkgs,
  ...
}:
{
  # Boot/kernel settings shared by every Raspberry Pi storage module
  # (ssd.nix, sd.nix). Plain priorities beat the rpi base module's mkDefault
  # ("uboot" bootloader, vendor kernel); the minimal installer (installer.nix)
  # overrides with mkForce where it needs the stock kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.raspberry-pi = {
    bootloader = "kernel";
    configurationLimit = 2;
  };
  boot.kernelParams = [ "rootwait" ];
  fileSystems."/boot/firmware".neededForBoot = true;
  services.fstrim.enable = true;
}
