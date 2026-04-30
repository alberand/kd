# Exiting VM
#   Use 'poweroff' command instead of CTRL-A X. Using the latter could lead to
#   corrupted root image and your VM won't boot (not always). However, it is
#   easily fixable by removing the image and running the VM again. The root
#   image is qcow2 file generated during the first run of your VM.
# Kernel Config:
#   Note that your kernel must have some features enabled. The list of features
#   could be found here https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/qemu-vm.nix#L1142
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/minimal.nix")
  ];
  boot = {
    kernelParams = [
      # consistent eth* naming
      "net.ifnames=0"
      "biosdevnames=0"
      "console=ttyS0,115200n8"
      "console=ttyS0"
    ];
    consoleLogLevel = lib.mkDefault 7;
    # This is happens before systemd
    # postBootCommands = "echo 'Not much to do before systemd :)' > /dev/kmsg";
    crashDump.enable = true;
    initrd.systemd.emergencyAccess = true;
  };

  # Do something after systemd started
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = ["getty.target"]; # to start at boot
    serviceConfig.Restart = "always"; # restart when session is closed
  };

  services.getty.autologinUser = "root";
  users.users.root.initialPassword = "";

  systemd.network.enable = lib.mkForce false;
  networking.networkmanager.enable = false;
  networking.firewall.enable = false;
  networking.hostName = lib.mkDefault "kd";
  networking.useDHCP = false;
  networking.dhcpcd.enable = false;
  services.resolved.enable = false;

  services.nscd.enable = false;
  system.nssModules = lib.mkForce [];
  services.logrotate.enable = false;
  security.audit.enable = false;
  services.speechd.enable = false;
  hardware.graphics.enable = false;
  services.pipewire.enable = false;
  services.libinput.enable = false;

  fonts.enableDefaultPackages = false;
  fonts.fontconfig.enable = false;
  fonts.packages = lib.mkForce [ pkgs.dejavu_fonts ];

  programs.bcc.enable = false;
  services.pulseaudio.enable = false;
  services.openssh.enable = false;

  # Add packages to VM
  environment.systemPackages = with pkgs; [
    util-linux
    fsverity-utils
    trace-cmd
    usbutils
    xxd
    xterm
    lvm2
    fscrypt-experimental
    lsof
  ];

  environment.variables.EDITOR = "nvim";

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  system.stateVersion = "25.11";
}
