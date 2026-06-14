{ ... }:
{
  networking.hostName = "dathomir";

  system.stateVersion = "24.11";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.cloud-init.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # TODO: Replace with your public SSH key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA.... your-key-here"
    ];
  };

  security.sudo.wheelNeedsPassword = false;
}
