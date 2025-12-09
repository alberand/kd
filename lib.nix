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
        ({config, ...}: {
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
            test-dev = pkgs.lib.mkDefault "/dev/vdb";
            scratch-dev = pkgs.lib.mkDefault "/dev/vdc";
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
        })
      ];
      format = "vm";
    };

  mkIso = {
    pkgs,
    uconfig,
  }:
    builtins.getAttr "iso" {
      iso = nixos-generators.nixosGenerate {
        inherit pkgs;
        system = "x86_64-linux";
        modules = [
          ./xfstests/module.nix
          ./xfsprogs/module.nix
          ./system.nix
          ./input.nix
          ({...}: uconfig)
          ({pkgs, ...}: {
            kernel.flavors = [pkgs.kconfigs.iso];

            services.xfsprogs.enable = true;
            # Don't shutdown system as libvirtd will remove the VM
            services.xfstests.autoshutdown = false;

            services.xfstests = {
              enable = true;
              test-dev = pkgs.lib.mkDefault "/dev/sda";
              scratch-dev = pkgs.lib.mkDefault "/dev/sdb";
            };
          })
        ];
        format = "iso";
      };
    };

  mkQcow = {
    pkgs,
    uconfig,
  }:
    builtins.getAttr "qcow" {
      qcow = nixos-generators.nixosGenerate {
        inherit pkgs;
        system = "x86_64-linux";
        modules = [
          ./xfstests/module.nix
          ./xfsprogs/module.nix
          ./system.nix
          ./input.nix
          ({...}: uconfig)
          ({
            config,
            pkgs,
            ...
          }: {
            kernel.flavors = [pkgs.kconfigs.iso];

            services.xfsprogs = {
              enable = true;
            };

            services.xfstests = {
              enable = true;
              autoshutdown = false;
              test-dev = pkgs.lib.mkDefault "/dev/sda";
              scratch-dev = pkgs.lib.mkDefault "/dev/sdb";
            };
          })
        ];
        format = "qcow";
      };
    };

  mkVmTest = {
    pkgs,
    name,
    uconfig,
  }:
    builtins.getAttr "runner" rec {
      inherit name;
      nixos = mkVM {
        inherit pkgs uconfig;
      };

      runner =
        pkgs.writeShellScriptBin "runner"
        ''
          # TODO find where .kd is
          # ROOTDIR="$(git rev-parse --show-toplevel)"
          export ROOTDIR="$PWD"
          export ENVNAME="${name}"
          export ENVDIR="$ROOTDIR/.kd/$ENVNAME"
          export LOCAL_CONFIG="$ROOTDIR/.kd.toml"
          export RUNDIR="$ENVDIR/share"
          export LOG_FILE="$RUNDIR/execution_$(date +"%Y-%m-%d_%H-%M").log"

          function eecho() {
            echo "$1" | tee -a $LOG_FILE
          }

          rm -rf "$RUNDIR/results"
          rm -rf "$RUNDIR/script.sh"
          mkdir -p $RUNDIR
          mkdir -p $RUNDIR/results

          if [ -f "$LOCAL_CONFIG" ]; then
            cp "$LOCAL_CONFIG" "$RUNDIR/kd.toml"

            if ! ${pkgs.tomlq}/bin/tq --file $LOCAL_CONFIG . > /dev/null; then
              echo "Invalid $LOCAL_CONFIG"
              exit 1
            fi

            if ${pkgs.tomlq}/bin/tq --file $LOCAL_CONFIG 'script' > /dev/null; then
              export SCRIPT_TEST="$(${pkgs.tomlq}/bin/tq --file $LOCAL_CONFIG 'script.script')"
            fi

            if [[ -f "$SCRIPT_TEST" ]]; then
              eecho "$SCRIPT_TEST will be used as simple test"
              cp "$SCRIPT_TEST" "$RUNDIR/script.sh"
            fi
          fi

          export NIX_DISK_IMAGE="$ENVDIR/image.qcow2"
          # After this line nix will insert more bash code. Don't exit
          # TODO this has to be proper name
          ${nixos}/bin/run-*-vm 2>&1 | tee -a $LOG_FILE
          echo "View results at $RUNDIR/results"
          echo "Log is in $LOG_FILE"
        '';
    };

  mkLinuxShell = {
    clangVersion ? "",
    gcc ? false,
    gccVersion ? "",
    packages ? [],
  }:
    builtins.getAttr "shell" {
      shell = pkgs.mkShell ({
          nativeBuildInputs = with pkgs;
            [
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
              python312Packages.ply # b4 prep --check and ./script/checkpatch
              python312Packages.gitpython # b4 prep --check and ./script/checkpatch
              (vmtest-deploy {})

              (callPackage (import ./kd/derivation.nix) {})
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
              (smatch.overrideAttrs (final: prev: {
                version = "git";
                src = fetchgit {
                  url = "git://repo.or.cz/smatch.git";
                  rev = "b8540ba87345cda269ef4490dd533aa6e8fb9229";
                  hash = "sha256-LQhNwhSbEP3BjBrT3OFjOjAoJQ1MU0HhyuBQPffOO48=";
                };
              }))
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
          ROOTDIR = "$(git rev-parse --show-toplevel)";

          shellHook = ''
            export MAKEFLAGS="-j$(nproc)"

            export AWK=$(type -P awk)
            export ECHO=$(type -P echo)
            export LIBTOOL=$(type -P libtool)
            export MAKE=$(type -P make)
            export SED=$(type -P sed)
            export SORT=$(type -P sort)

            echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
          '';
        }
        // (pkgs.lib.optionalAttrs (!gcc) {
          LLVM = 1;
        }));
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
    name,
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
    kconfig-iso = kconfigBuild {config = "iso";};

    headers = buildKernelHeaders {
      inherit src version;
    };

    kernel = buildKernel {
      inherit src kconfig version;
    };

    iso = mkIso {
      inherit pkgs;
      uconfig =
        {
          networking.hostName = "${name}";
          kernel = {
            inherit src version;
            kconfig = kconfig-iso.structuredConfig;
          };

          services.xfstests = {
            arguments = "-R xunit -s xfs_4k generic/110";
          };
        }
        // uconfig;
    };

    qcow = mkQcow {
      inherit pkgs;
      uconfig =
        {
          networking.hostName = "${name}";
          services.xfstests = {
            arguments = "-R xunit -s xfs_4k generic/110";
          };
          boot.initrd.kernelModules = pkgs.lib.mkForce [
            "virtio_balloon"
            "virtio_console"
            "virtio_rng"
          ];
        }
        // uconfig;
    };

    vm = mkVmTest {
      inherit pkgs name;
      uconfig =
        {
          networking.hostName = "${name}";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.workdir = "$ENVDIR";
          vm.disks = [12000 12000 2000 2000];
        }
        // uconfig;
    };

    prebuild = mkVmTest {
      inherit pkgs name;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "${name}-prebuild";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.workdir = "$ENVDIR";
          vm.disks = [12000 12000 2000 2000];

          # As our dummy derivation doesn't provide any .config we need to tell
          # NixOS not to check for any required configurations
          system.requiredKernelConfig = pkgs.lib.mkForce [];
        }
        // uconfig;
    };

    kgdbvm = mkVmTest {
      inherit pkgs name;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "${name}-kgdb";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.workdir = "$ENVDIR";
          vm.disks = [12000 12000 2000 2000];

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

    shell = mkLinuxShell { };

    shell-clang20 = mkLinuxShell {
      clangVersion = "20";
    };

    shell-clang18 = mkLinuxShell {
      clangVersion = "18";
    };

    shell-gcc = mkLinuxShell {
      gcc = true;
    };

    shell-gcc15 = mkLinuxShell {
      gcc = true;
      gccVersion = "15";
    };

    shell-gcc14 = mkLinuxShell {
      gcc = true;
      gccVersion = "14";
    };

    shell-gcc13 = mkLinuxShell {
      gcc = true;
      gccVersion = "13";
    };
  };
}
