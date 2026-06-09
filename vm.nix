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
      diskSize = lib.mkDefault 30000; # MB
      # Store the image in sharedir instead of pwd
      memorySize = lib.mkDefault 4096; # MB
      cores = lib.mkDefault 4;
      writableStoreUseTmpfs = lib.mkDefault false;
      useDefaultFilesystems = lib.mkDefault true;
      # Run qemu in the terminal not in Qemu GUI
      graphics = lib.mkDefault false;
      emptyDiskImages = lib.mkDefault [
        12000
        12000
        1000
        1000
        1000
        1000
      ];
      diskImage = lib.mkDefault "$ENVDIR/${config.system.name}.qcow2";
    };
  };
}
