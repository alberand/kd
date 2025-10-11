{
  config,
  lib,
  ...
}: let
  cfg = config.vm;
in {
  options.vm = {
    workdir = lib.mkOption {
      description = "Work dir for creating disk image and share mount";
      example = "/tmp/kd";
      default = ".kd/default";
      type = lib.types.str;
    };

    qemu-options = lib.mkOption {
      description = "QEMU command line options";
      default = [];
      example = "-serial stdio";
      type = lib.types.listOf lib.types.str;
    };

    disks = lib.mkOption {
      description = "Create empty disks of specified size";
      default = [];
      example = "[5000 5000]";
      type = lib.types.listOf lib.types.int;
    };
  };

  config = {
    boot.kernelModules = lib.mkForce [];
    boot.initrd = {
      # Override required kernel modules by nixos/modules/profiles/qemu-guest.nix
      # As we use kernel build outside of Nix, it will have different uname and
      # will not be able to find these modules. This probably can be fixed
      availableKernelModules = lib.mkForce [];
      kernelModules = lib.mkForce [];
    };
    virtualisation = {
      diskSize = 20000; # MB
      # Store the image in sharedir instead of pwd
      memorySize = 4096; # MB
      cores = 4;
      writableStoreUseTmpfs = false;
      useDefaultFilesystems = true;
      # Run qemu in the terminal not in Qemu GUI
      graphics = false;

      emptyDiskImages = cfg.disks;
    };
  };
}
