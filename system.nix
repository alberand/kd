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
  ...
}: {
  boot = {
    kernelParams = [
      # consistent eth* naming
      "net.ifnames=0"
      "biosdevnames=0"
      "console=ttyS0,115200n8"
      "console=tty0"
    ];
    consoleLogLevel = lib.mkDefault 7;
    # This is happens before systemd
    # postBootCommands = "echo 'Not much to do before systemd :)' > /dev/kmsg";
    crashDump.enable = true;
    initrd = {
      enable = true;
    };
  };

  # Do something after systemd started
  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = ["getty.target"]; # to start at boot
    serviceConfig.Restart = "always"; # restart when session is closed
  };
  # Auto-login with empty password
  users.extraUsers.root.initialHashedPassword = "$y$j9T$TKzQNuxk898Qk7J6JC5NU1$xDW5NFyr0H/wW/k/MaTpbCRIMEsv.SbvBbj6Wu/1060"; # notsecret
  services.getty.autologinUser = lib.mkDefault "root";

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

  # Not needed in VM
  documentation.doc.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
  documentation.info.enable = false;
  programs.command-not-found.enable = false;

  # Add packages to VM
  environment.systemPackages = with pkgs; [
    htop
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

  programs.bcc.enable = false;
  services.pulseaudio.enable = false;

  environment.variables = {
    EDITOR = "nvim";
  };

  services.openssh = {
    enable = false;
  };

  system.tools = {
    nixos-generate-config.enable = false;
    nixos-rebuild.enable = false;
  };

  programs.bash.interactiveShellInit = let
    motd =
      pkgs.writeShellScriptBin "motd"
      ''
        #!/usr/bin/env bash

        echo "QEMU exit CTRL-A X"
        echo "libvirtd exit CTRL+]"

        echo "xfsprogs: ${pkgs.xfsprogs.version}"
        echo "source: ${pkgs.xfsprogs.src}"
        echo "${builtins.toJSON pkgs.xfsprogs.src}" | ${pkgs.jq}/bin/jq

        echo "xfstests: ${pkgs.xfstests.version}"
        echo "source: ${pkgs.xfstests.src}"
        echo "${builtins.toJSON pkgs.xfstests.src}" | ${pkgs.jq}/bin/jq
      '';
  in
    builtins.readFile "${motd}/bin/motd";

  system.stateVersion = "25.05";
}
