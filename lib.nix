{
  pkgs,
  nixosSystem,
}: let
in rec {
  mkVmImage = {user-modules}:
    (nixosSystem {
      inherit pkgs;
      system = "x86_64-linux";
      modules =
        [
          ./xfstests/module.nix
          ./xfsprogs/module.nix
          ./system.nix
          ./vm.nix
          ./input.nix
          (
            {config, ...}: {
              virtualisation.sharedDirectories = {
                share = {
                  source = "$ENVDIR/share";
                  target = "/root/share";
                };
              };
            }
          )
        ]
        ++ user-modules;
    }).config.system.build.vm;

  buildKernelHeaders = pkgs.makeLinuxHeaders;

  mkEnv = {
    useGcc ? false,
    user-modules ? [],
  }: let
    stdenv =
      if useGcc
      then pkgs.stdenv
      else pkgs.clangStdenv;
    buildKernelConfig = pkgs.callPackage ./kernel-config.nix {
      inherit stdenv;
    };
    buildKernel = pkgs.callPackage ./kernel-build.nix {
      inherit stdenv;
    };
    sources = (import ./input.nix) {
      inherit pkgs;
      config = {};
    };
    userSystem =
      (nixosSystem {
        inherit pkgs;
        system = "x86_64-linux";
        modules =
          [
            ./xfstests/module.nix
            ./xfsprogs/module.nix
            ./system.nix
            ./vm.nix
            ./input.nix
          ]
          ++ user-modules;
      }).config;
    useConfig = builtins.hasAttr "kernel" userSystem;
    version =
      if useConfig && builtins.hasAttr "version" userSystem.kernel
      then userSystem.kernel.version
      else sources.options.kernel.version.default;
    src =
      if useConfig && builtins.hasAttr "src" userSystem.kernel
      then userSystem.kernel.src
      else sources.options.kernel.src.default;
    kkconfig =
      if useConfig && builtins.hasAttr "kconfig" userSystem.kernel
      then userSystem.kernel.kconfig
      else sources.options.kernel.kconfig.default;
    kconfigBuild = {config}:
      buildKernelConfig {
        inherit src version;
        kconfig = kkconfig // pkgs.kconfigs."${config}";
      };
  in rec {
    inherit (pkgs) xfsprogs xfstests;

    kconfig = buildKernelConfig {
      inherit src version;
      kconfig = kkconfig;
    };

    kconfig-debug = kconfigBuild {config = "debug";};
    kconfig-image = kconfigBuild {config = "image";};

    headers = buildKernelHeaders {
      inherit src version;
    };

    kernel = buildKernel {
      inherit src kconfig version;
    };

    vm = pkgs.callPackage ./runner.nix {
      nixos = mkVmImage {
        user-modules =
          user-modules
          ++ [
            (
              {...}: {
                kernel = pkgs.lib.mkDefault {
                  inherit src version;
                  kconfig = kkconfig;
                };
              }
            )
          ];
      };
    };

    prebuild = pkgs.callPackage ./runner.nix {
      nixos = mkVmImage {
        user-modules =
          user-modules
          ++ [
            (
              {...}: {
                kernel = pkgs.lib.mkDefault {
                  inherit src version;
                  kconfig = kkconfig;
                };

                # As our dummy derivation doesn't provide any .config we need to tell
                # NixOS not to check for any required configurations
                system.requiredKernelConfig = pkgs.lib.mkForce [];
              }
            )
          ];
      };
    };

    kgdbvm = pkgs.callPackage ./runner.nix {
      nixos = mkVmImage {
        user-modules =
          user-modules
          ++ [
            (
              {...}: {
                kernel = pkgs.lib.mkDefault {
                  inherit src version;
                  kconfig = kkconfig;
                };

                boot.kernelParams = pkgs.lib.mkForce [
                  # consistent eth* naming
                  "net.ifnames=0"
                  "biosdevnames=0"
                  "console=tty0"
                  "kgdboc=ttyS0,115200"
                  "nokaslr"
                  "kgdbwait"
                ];

                # As our dummy derivation doesn't provide any .config we need to tell
                # NixOS not to check for any required configurations
                system.requiredKernelConfig = pkgs.lib.mkForce [];
              }
            )
          ];
      };
    };

    #initrd = pkgs.callPackage (import ./initrd/default.nix) {
    #  inherit nixpkgs;
    #};

    image =
      (nixosSystem {
        inherit pkgs;
        system = "x86_64-linux";
        modules =
          [
            ./xfstests/module.nix
            ./xfsprogs/module.nix
            ./input.nix
            ./system.nix
            ./image.nix
            (
              {config, ...}: {
                systemd.repart.partitions = {
                  test = {
                    Format = "ext4";
                    Label = "test";
                    SizeMinBytes = "1G";
                    SizeMaxBytes = "10G";
                    Type = "linux-generic";
                    Weight = 500;
                  };
                  scratch = {
                    Format = "ext4";
                    Label = "scratch";
                    SizeMinBytes = "1G";
                    SizeMaxBytes = "10G";
                    Type = "linux-generic";
                    Weight = 500;
                  };
                };

                services.xfstests = {
                  dev = {
                    test = {
                      main = pkgs.lib.mkDefault "/dev/sda5";
                    };
                    scratch = {
                      main = pkgs.lib.mkDefault "/dev/sda4";
                    };
                  };
                };
              }
            )
          ]
          ++ user-modules;
      }).config.system.build.image;

    run-image = pkgs.callPackage ./run-image.nix {
      inherit image;
    };
  };
}
