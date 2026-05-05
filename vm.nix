{
  config,
  lib,
  modulesPath,
  ...
}: let
  cfg = config.vm;
in {
  imports = [
    (modulesPath + "/virtualisation/qemu-vm.nix")
  ];

  config = {
    virtualisation = {
      diskSize = 20000; # MB
      # Store the image in sharedir instead of pwd
      memorySize = 4096; # MB
      cores = 4;
      writableStoreUseTmpfs = false;
      useDefaultFilesystems = true;
      # Run qemu in the terminal not in Qemu GUI
      graphics = false;
      diskImage = "$ENVDIR/${config.system.name}.qcow2";
      qemu = {
        # Network requires tap0 netowrk on the host
        options = [];
          #[
          #  "-device e1000,netdev=network0,mac=00:00:00:00:00:00"
          #  "-netdev tap,id=network0,ifname=tap0,script=no,downscript=no"
          #  "-device virtio-rng-pci"
          #];
      };

     sharedDirectories = {
        share = {
          source = "$ENVDIR/share";
          target = "/root/share";
        };
      };
    };
  };
}
