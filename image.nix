{
  pkgs,
  config,
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/profiles/image-based-appliance.nix")
    (modulesPath + "/image/repart.nix")
  ];

  fileSystems = {
    "/" = {
      fsType = "tmpfs";
      options = ["size=4G"];
    };
    "/boot" = {
      device = "/dev/disk/by-partlabel/boot";
      fsType = "vfat";
    };
    "/nix/store" = {
      device = "/dev/disk/by-partlabel/nix-store";
      fsType = "erofs";
      # TODO report this to nixpkgs.
      # This is needed because /dev/sda2 aka nix-store somehow isn't there when
      # sysroot-nix-store.mount runs. This is systemd-generated fstab mount. It
      # has all the dependencies on the partition. One theory is that,
      # systemd-repart needs sysroot but sysroot can not mount /nix/store before
      # systemd-repart??? Or maybe there need for dependcy ont the
      # sysroot-nix-store.mount, I tried a few different ones and none of them
      # worked.
      options = ["x-systemd.after=systemd-repart.service"];
    };
    "/home" = {
      device = "/dev/disk/by-partlabel/home";
      fsType = "ext4";
    };
    "/var" = {
      device = "/dev/disk/by-partlabel/var";
      fsType = "ext4";
    };
  };

  image.repart = let
    inherit (pkgs.stdenv.hostPlatform) efiArch;
  in {
    name = "image";

    partitions = {
      esp = {
        contents = {
          "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";

          "/EFI/Linux/${config.system.boot.loader.ukiFile}".source = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
        };
        repartConfig = {
          Format = "vfat";
          Label = "boot";
          SizeMinBytes = "60M";
          Type = "esp";
          UUID = "a0b1c2d3-e4f5-6a7b-8c9d-0e1f2a3b4c5d";
        };
      };
      nix-store = {
        storePaths = [config.system.build.toplevel];
        nixStorePrefix = "/";
        repartConfig = {
          Format = "erofs";
          Label = "nix-store";
          Minimize = "guess";
          ReadOnly = "yes";
          Type = "linux-generic";
        };
      };
    };
  };

  boot.initrd.systemd.repart.enable = true;
  boot.initrd.systemd.repart.device = pkgs.lib.mkDefault "/dev/sda";
  systemd.repart.partitions = {
    # Systemd-repart is trying to reuse /nix/store partition for any other
    # suitable partition. This tells systemd-repart that this partition should
    # not be touched. Same for boot.
    boot = {
      Label = "boot";
      Type = "esp";
      Priority = -1;
      UUID = "a0b1c2d3-e4f5-6a7b-8c9d-0e1f2a3b4c5d";
    };
    nix-store = {
      Label = "nix-store";
      Type = "linux-generic";
      Priority = -1;
      UUID = "b1c2d3e4-f5a6-7b8c-9d0e-1f2a3b4c5d6e";
    };
    home = {
      Format = "ext4";
      Label = "home";
      Type = "home";
      SizeMinBytes = "3G";
      SizeMaxBytes = "3G";
      Weight = 500;
      UUID = "c2d3e4f5-a6b7-8c9d-0e1f-2a3b4c5d6e7f";
    };
    var = {
      Format = "ext4";
      Label = "var";
      Type = "var";
      SizeMinBytes = "3G";
      SizeMaxBytes = "3G";
      Weight = 500;
      UUID = "d3e4f5a6-b7c8-9d0e-1f2a-3b4c5d6e7f80";
    };
  };
}
