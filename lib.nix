{
  pkgs,
  nixos-generators,
  nixpkgs,
}: let
  mkLlvmPkgs = {clangVersion}: let
    llvmPackages =
      if clangVersion != ""
      then pkgs."llvmPackages_${clangVersion}"
      else pkgs."llvmPackages_latest";
  in
    with llvmPackages; [
      clang
      clang-tools
      libllvm
    ];
  mkGccPkgs = {gccVersion ? ""}: [
    (
      if gccVersion != ""
      then pkgs."gcc${gccVersion}"
      else pkgs."gcc"
    )
  ];
in rec {
  mkVM = {
    pkgs,
    uconfig,
  }:
    nixos-generators.nixosGenerate {
      inherit pkgs;
      system = "x86_64-linux";
      specialArgs = {
        diskSize = "20000";
      };
      modules = [
        ./xfstests/module.nix
        ./xfsprogs/module.nix
        ./script/module.nix
        ./system.nix
        ./vm.nix
        ./input.nix
        ({...}: uconfig)
        (
          {config, ...}: {
            #assertions = [
            #  {
            #    assertion = config.kernel.prebuild != null;
            #    message = "kernel.prebuild should be set to path with built kernel";
            #  }
            #];

            services.xfsprogs = {
              enable = true;
            };

            services.script = {
              enable = true;
            };

            services.xfstests = {
              enable = true;
              dev = {
                test = {
                  main = pkgs.lib.mkDefault "/dev/vdb";
                  #rtdev = pkgs.lib.mkDefault "/dev/vdf";
                  #logdev = pkgs.lib.mkDefault "/dev/vdg";
                };
                scratch = {
                  main = pkgs.lib.mkDefault "/dev/vdc";
                  # rtdev = pkgs.lib.mkDefault "/dev/vdd";
                  # logdev = pkgs.lib.mkDefault "/dev/vde";
                };
              };
            };

            virtualisation = {
              diskImage = "${config.vm.workdir}/${config.system.name}.qcow2";
              qemu = {
                # Network requires tap0 netowrk on the host
                options =
                  [
                    "-device e1000,netdev=network0,mac=00:00:00:00:00:00"
                    "-netdev tap,id=network0,ifname=tap0,script=no,downscript=no"
                    "-device virtio-rng-pci"
                  ]
                  ++ config.vm.qemu-options;
              };

              sharedDirectories = {
                share = {
                  source = "${config.vm.workdir}/share";
                  target = "/root/share";
                };
              };
            };
          }
        )
      ];
      format = "vm";
    };

  mkVmTest = {
    pkgs,
    uconfig,
  }:
    builtins.getAttr "runner" rec {
      nixos = mkVM {
        inherit pkgs uconfig;
      };

      runner = pkgs.callPackage ./runner.nix {inherit nixos;};
    };

  mkLinuxShell = {
    clangVersion ? "",
    gcc ? false,
    gccVersion ? "",
    packages ? [],
    sources ? {},
  }:
    builtins.getAttr "shell" {
      shell = pkgs.mkShell (
        {
          nativeBuildInputs = with pkgs;
            [
              gitFull
              getopt
              flex
              bison
              perl
              gnumake
              bc
              pkg-config
              binutils
              elfutils
              ncurses
              lld
              gettext
              libtool
              automake
              autoconf
              pahole
              trace-cmd
              #python312Packages.ply # b4 prep --check and ./script/checkpatch
              #python312Packages.gitpython # b4 prep --check and ./script/checkpatch
              b4
              patchutils_0_4_2
              (vmtest-deploy {})

              (callPackage (import ./kd/derivation.nix) {
                inherit (pkgs.lib) makeBinPath fileset;
              })
              smatch
            ]
            ++ (
              if gcc
              then (mkGccPkgs {inherit gccVersion;})
              else (mkLlvmPkgs {inherit clangVersion;})
            )
            ++ packages
            ++ lib.optional false [
              file
              e2fsprogs
              attr
              acl
              libaio
              keyutils
              fsverity-utils
              ima-evm-utils
              util-linux
              stress-ng
              fio
              linuxquota
              nvme-cli
              virt-manager # for deploy
              xmlstarlet
              rpm
              sphinx # for btrfs-progs
              zstd # for btrfs-progs
              udev # for btrfs-progs
              lzo # for btrfs-progs
              ctags
              jq
              liburing # for btrfs-progs
              python312
              python312Packages.flake8
              python312Packages.pylint
              cargo
              rustc
              # kselftest deps
              libcap
              libcap_ng
              fuse3
              fuse
              alsa-lib
              libmnl
              numactl
              guilt
              nix-prefetch-git
              tomlq
              # probably better to move it to separate module
              sqlite
              openssl
              libllvm
              libxml2.dev
              perl
              perl538Packages.DBI
              perl538Packages.DBDSQLite
              perl538Packages.TryTiny
            ];

          buildInputs = with pkgs; [
            elfutils
            ncurses
            openssl
            zlib
          ];

          KBUILD_BUILD_TIMESTAMP = "";
          # Disable all automatically applied hardening. The Linux
          # kernel will take care of itself.
          NIX_HARDENING_ENABLE = "";
          SOURCE_DATE_EPOCH = 0;
          CCACHE_MAXSIZE = "5G";
          CCACHE_DIR = "$HOME/.cache/ccache/";
          CCACHE_SLOPPINESS = "random_seed";
          CCACHE_UMASK = 007;

          shellHook = let
            xfsprogs-version = (pkgs.lib.importJSON ./sources/xfsprogs.json).rev;
            xfstests-version = (pkgs.lib.importJSON ./sources/xfstests.json).rev;
          in ''
            export MAKEFLAGS="-j$(nproc)"

            export AWK=$(type -P awk)
            export ECHO=$(type -P echo)
            export LIBTOOL=$(type -P libtool)
            export MAKE=$(type -P make)
            export SED=$(type -P sed)
            export SORT=$(type -P sort)

            echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
            echo "Envrionment has:"
            echo -e "\tkernel: ${sources.options.kernel.version.default}"
            echo -e "\txfsprogs: ${xfsprogs-version}"
            echo -e "\txfstests: ${xfstests-version}"
          '';
        }
        // (pkgs.lib.optionalAttrs (!gcc) {
          LLVM = 1;
        })
      );
    };

  mkXfsprogsShell = {}:
    pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        acl
        attr
        automake
        autoconf
        bc
        dump
        e2fsprogs
        fio
        gawk
        indent
        libtool
        file
        gnumake
        pkg-config
        libuuid
        gawk
        libuuid
        libxfs
        gdbm
        icu
        libuuid # codegen tool uses libuuid
        liburcu # required by crc32selftest
        readline
        inih
        man
        gettext
        patchutils_0_4_2
        (mkLlvmPkgs {clangVersion = "19";})
      ];

      KBUILD_BUILD_TIMESTAMP = "";
      SOURCE_DATE_EPOCH = 0;
      CCACHE_DIR = "$HOME/.cache/ccache/";
      CCACHE_SLOPPINESS = "random_seed";
      CCACHE_UMASK = 007;

      shellHook = ''
        export MAKEFLAGS="-j$(nproc)"
        echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
      '';
    };

  mkXfstestsShell = {}:
    pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        udev
        flex
        bison
        perl
        gnumake
        pkg-config
        lld
        file
        gettext
        libtool
        automake
        autoconf
        attr
        acl
        libxfs
        libaio
        icu
        libuuid
        liburcu
        liburing
        readline
        gnutar
        gzip
        (mkLlvmPkgs {clangVersion = "19";})
      ];

      KBUILD_BUILD_TIMESTAMP = "";
      SOURCE_DATE_EPOCH = 0;
      CCACHE_DIR = "$HOME/.cache/ccache/";
      CCACHE_SLOPPINESS = "random_seed";
      CCACHE_UMASK = 007;

      shellHook = ''
        export MAKEFLAGS="-j$(nproc)"
        echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
      '';
    };

  buildKernelHeaders = pkgs.makeLinuxHeaders;

  vmtest-deploy = {}:
    builtins.getAttr "script" {
      script = pkgs.writeScriptBin "vmtest-deploy" (builtins.readFile ./deploy.sh);
    };

  mkEnv = {
    nixpkgs,
    useGcc ? false,
    uconfig ? {},
  }: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        (import ./xfsprogs/overlay.nix)
        (import ./xfstests/overlay.nix)
        (final: prev: {
          kconfigs = import ./kconfigs/default.nix {inherit (pkgs) lib;};
        })
      ];
    };
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
    useConfig = builtins.hasAttr "kernel" uconfig;
    version =
      if useConfig && builtins.hasAttr "version" uconfig.kernel
      then uconfig.kernel.version
      else sources.options.kernel.version.default;
    src =
      if useConfig && builtins.hasAttr "src" uconfig.kernel
      then uconfig.kernel.src
      else sources.options.kernel.src.default;
    kkconfig =
      if useConfig && builtins.hasAttr "kconfig" uconfig.kernel
      then uconfig.kernel.kconfig
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

    vm = mkVmTest {
      inherit pkgs;
      uconfig =
        {
          networking.hostName = "kd";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.workdir = "$ENVDIR";
          vm.disks = [
            12000
            12000
            1000
            1000
            1000
            1000
          ];
        }
        // uconfig;
    };

    prebuild = mkVmTest {
      inherit pkgs;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "kd";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.workdir = "$ENVDIR";
          vm.disks = [
            12000
            12000
            1000
            1000
            1000
            1000
          ];

          # As our dummy derivation doesn't provide any .config we need to tell
          # NixOS not to check for any required configurations
          system.requiredKernelConfig = pkgs.lib.mkForce [];
        }
        // uconfig;
    };

    kgdbvm = mkVmTest {
      inherit pkgs;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "kd";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.workdir = "$ENVDIR";
          vm.disks = [
            12000
            12000
            1000
            1000
            1000
            1000
          ];

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
        // uconfig;
    };

    #initrd = pkgs.callPackage (import ./initrd/default.nix) {
    #  inherit nixpkgs uconfig;
    #};

    shell = mkLinuxShell {inherit sources;};

    shell-clang20 = mkLinuxShell {
      inherit sources;
      clangVersion = "20";
    };

    shell-clang18 = mkLinuxShell {
      inherit sources;
      clangVersion = "18";
    };

    shell-gcc = mkLinuxShell {
      inherit sources;
      gcc = true;
    };

    shell-gcc15 = mkLinuxShell {
      inherit sources;
      gcc = true;
      gccVersion = "15";
    };

    shell-gcc14 = mkLinuxShell {
      inherit sources;
      gcc = true;
      gccVersion = "14";
    };

    shell-gcc13 = mkLinuxShell {
      inherit sources;
      gcc = true;
      gccVersion = "13";
    };

    image =
      (nixpkgs.lib.nixosSystem {
        inherit pkgs;
        system = "x86_64-linux";
        modules = [
          ./image.nix
          {nixpkgs.hostPlatform = "x86_64-linux";}
          ./xfstests/module.nix
          ./xfsprogs/module.nix
          ./system.nix
          ./input.nix
          ({...}: uconfig)
          (
            {config, ...}: {
              boot.kernelModules = nixpkgs.lib.mkForce [];
              boot.initrd = {
                # Override required kernel modules by
                # nixos/modules/profiles/qemu-guest.nix As we use kernel build
                # outside of Nix, it will have different uname and will not be
                # able to find these modules. This probably can be fixed
                availableKernelModules = nixpkgs.lib.mkForce [];
                kernelModules = nixpkgs.lib.mkForce [];
              };

              services.xfsprogs = {
                enable = true;
              };

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
                enable = true;
                arguments = pkgs.lib.mkDefault "-R xunit -s xfs_4k generic/110";
                dev = {
                  test = {
                    main = pkgs.lib.mkDefault "/dev/sda5";
                    #rtdev = pkgs.lib.mkDefault "/dev/vdf";
                    #logdev = pkgs.lib.mkDefault "/dev/vdg";
                  };
                  scratch = {
                    main = pkgs.lib.mkDefault "/dev/sda4";
                    # rtdev = pkgs.lib.mkDefault "/dev/vdd";
                    # logdev = pkgs.lib.mkDefault "/dev/vde";
                  };
                };
              };
            }
          )
        ];
      }).config.system.build.image;

    run-image = pkgs.callPackage ./run-image.nix {
      inherit image;
    };
  };
}
