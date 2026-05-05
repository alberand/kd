{
  pkgs,
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
  mkVmImage = {
    pkgs,
    user-modules,
  }:
    (nixpkgs.lib.nixosSystem {
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
    }).config.system.build.vm;

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
            ++ packages;

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
    user-modules ? [],
    user-overlays ? [],
  }: let
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [
        (import ./xfsprogs/overlay.nix)
        (import ./xfstests/overlay.nix)
        (final: prev: {
          kconfigs = import ./kconfigs/default.nix {inherit (pkgs) lib;};
        })
      ] ++ user-overlays;
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
    userSystem = (nixpkgs.lib.nixosSystem {
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
        inherit pkgs;
        user-modules = user-modules ++ [
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
        inherit pkgs;
        user-modules = user-modules ++ [
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
        inherit pkgs;
        user-modules = user-modules ++ [
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
        modules =
          [
            {nixpkgs.hostPlatform = "x86_64-linux";}
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
