{
  pkgs,
  nixos-generators,
  nixpkgs,
}: let
  llvm = with pkgs; [
    clang
    clang-tools
    libllvm
  ];
  gcc = with pkgs; [
    gcc
  ];
in rec {
  mkVM = {uconfig}:
    nixos-generators.nixosGenerate {
      inherit pkgs;
      system = "x86_64-linux";
      specialArgs = {
        diskSize = "20000";
      };
      modules = [
        ./xfstests/xfstests.nix
        ./xfsprogs.nix
        ./dummy.nix
        ./system.nix
        ./vm.nix
        (pkgs.callPackage (import ./input.nix) {inherit nixpkgs;})
        ({...}: uconfig)
        ({config, ...}: {
          #assertions = [
          #  {
          #    assertion = config.kernel.prebuild != null;
          #    message = "kernel.prebuild should be set to path with built kernel";
          #  }
          #];

          programs.xfsprogs = {
            enable = true;
            kernelHeaders = buildKernelHeaders {
              inherit (config.kernel) src version;
            };
          };
          programs.dummy = {
            enable = true;
          };
          programs.xfstests = {
            enable = true;
            test-dev = pkgs.lib.mkDefault "/dev/vdb";
            scratch-dev = pkgs.lib.mkDefault "/dev/vdc";
            kernelHeaders = buildKernelHeaders {
              inherit (config.kernel) src version;
            };
          };
        })
      ];
      format = "vm";
    };

  mkIso = {uconfig}:
    builtins.getAttr "iso" {
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./xfstests/xfstests.nix
          ./xfsprogs.nix
          ./system.nix
          (pkgs.callPackage (import ./input.nix) {inherit nixpkgs;})
          ({...}: uconfig)
          ({pkgs, ...}: {
            kernel.iso = pkgs.lib.mkForce true;

            programs.xfsprogs.enable = true;
            # Don't shutdown system as libvirtd will remove the VM
            programs.xfstests.autoshutdown = false;

            programs.xfstests = {
              enable = true;
              test-dev = pkgs.lib.mkDefault "/dev/sda";
              scratch-dev = pkgs.lib.mkDefault "/dev/sdb";
            };
          })
        ];
        format = "iso";
      };
    };

  mkQcow = {uconfig}:
    builtins.getAttr "qcow" {
      qcow = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./xfstests/xfstests.nix
          ./xfsprogs.nix
          ./system.nix
          (pkgs.callPackage (import ./input.nix) {inherit nixpkgs;})
          ({...}: uconfig)
          ({pkgs, ...}: {
            kernel.iso = pkgs.lib.mkForce true;

            programs.xfsprogs.enable = true;
            # Don't shutdown system as libvirtd will remove the VM
            programs.xfstests.autoshutdown = false;

            programs.xfstests = {
              enable = true;
              test-dev = pkgs.lib.mkDefault "/dev/sda";
              scratch-dev = pkgs.lib.mkDefault "/dev/sdb";
            };
          })
        ];
        format = "qcow";
      };
    };

  mkVmTest = {
    name,
    root,
    uconfig,
  }:
    builtins.getAttr "runner" rec {
      inherit name root;
      nixos = mkVM {
        inherit uconfig;
      };

      runner =
        pkgs.writeShellScriptBin "runner"
        ''
          ROOTDIR="$(git rev-parse --show-toplevel)"
          ENVNAME="${name}"
          ENVDIR="$ROOTDIR/.kd/$ENVNAME"
          LOCAL_CONFIG="$ROOTDIR/.kd.toml"
          RUNDIR="$ENVDIR/share"
          LOG_FILE="$RUNDIR/execution_$(date +"%Y-%m-%d_%H-%M").log"

          function eecho() {
            echo "$1" | tee -a $LOG_FILE
          }

          rm -rf "$RUNDIR/results"
          rm -rf "$RUNDIR/dummy.sh"
          mkdir -p $RUNDIR
          mkdir -p $RUNDIR/results

          cp "$LOCAL_CONFIG" "$RUNDIR/kd.toml"

          if ! tq --file $LOCAL_CONFIG . > /dev/null; then
            echo "Invalid $LOCAL_CONFIG"
            exit 1
          fi

          if tq --file $LOCAL_CONFIG 'dummy' > /dev/null; then
            export DUMMY_TEST="$(tq --file $LOCAL_CONFIG 'dummy.script')"
          fi

          if [[ -f "$DUMMY_TEST" ]]; then
            eecho "$DUMMY_TEST will be used as simple test"
            cp "$DUMMY_TEST" "$RUNDIR/dummy.sh"
          fi

          export NIX_DISK_IMAGE="$ENVDIR/image.qcow2"
          # After this line nix will insert more bash code. Don't exit
          ${nixos}/bin/run-${name}-vm 2>&1 | tee -a $LOG_FILE
          echo "View results at $RUNDIR/results"
          echo "Log is in $LOG_FILE"
        '';
    };

  mkLinuxShell = {
    root,
    name,
    packages ? [],
  }:
    builtins.getAttr "shell" {
      shell = pkgs.mkShell {
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
            qemu_full
            qemu-utils
            automake
            autoconf
            pahole
            (vmtest-deploy {})

            (callPackage (import ./kd/derivation.nix) {})
          ]
          ++ llvm
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

        NODE_NAME = "${name}";
        KBUILD_BUILD_TIMESTAMP = "";
        SOURCE_DATE_EPOCH = 0;
        CCACHE_DIR = "/var/cache/ccache/";
        CCACHE_SLOPPINESS = "random_seed";
        CCACHE_UMASK = 777;
        ROOTDIR = "$(git rev-parse --show-toplevel)";

        NIX_HARDENING_ENABLE = "";

        shellHook = ''
          curdir="$(pwd)"
          if [ ! -f "$curdir/compile_commands.json" ] &&
              [ -f "$curdir/scripts/clang-tools/gen_compile_commands.py" ]; then
            "$curdir/scripts/clang-tools/gen_compile_commands.py"
          fi

          export LLVM=1
          export MAKEFLAGS="-j$(nproc)"
          if type -p ccache; then
            export CC="ccache clang"
            export HOSTCC="ccache clang"
          fi

          export AWK=$(type -P awk)
          export ECHO=$(type -P echo)
          export LIBTOOL=$(type -P libtool)
          export MAKE=$(type -P make)
          export SED=$(type -P sed)
          export SORT=$(type -P sort)

          echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
        '';
      };
    };

  mkXfsprogsShell = {}:
    pkgs.mkShell {
      nativeBuildInputs = with pkgs;
        [
          acl
          attr
          automake
          autoconf
          bc
          dbench
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
        ]
        ++ llvm;

      KBUILD_BUILD_TIMESTAMP = "";
      SOURCE_DATE_EPOCH = 0;
      CCACHE_DIR = "/var/cache/ccache/";
      CCACHE_SLOPPINESS = "random_seed";
      CCACHE_UMASK = 777;

      shellHook = ''
        export LLVM=1
        export MAKEFLAGS="-j$(nproc)"
        if type -p ccache; then
          export CC="ccache clang"
          export HOSTCC="ccache clang"
        fi

        export AWK=$(type -P awk)
        export ECHO=$(type -P echo)
        export LIBTOOL=$(type -P libtool)
        export MAKE=$(type -P make)
        export SED=$(type -P sed)
        export SORT=$(type -P sort)

        echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
      '';
    };

  mkXfstestsShell = {}:
    pkgs.mkShell {
      nativeBuildInputs = with pkgs;
        [
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
        ]
        ++ llvm;

      KBUILD_BUILD_TIMESTAMP = "";
      SOURCE_DATE_EPOCH = 0;
      CCACHE_DIR = "/var/cache/ccache/";
      CCACHE_SLOPPINESS = "random_seed";
      CCACHE_UMASK = 777;

      shellHook = ''
        export LLVM=1
        export MAKEFLAGS="-j$(nproc)"
        if type -p ccache; then
          export CC="ccache clang"
          export HOSTCC="ccache clang"
        fi

        export AWK=$(type -P awk)
        export ECHO=$(type -P echo)
        export LIBTOOL=$(type -P libtool)
        export MAKE=$(type -P make)
        export SED=$(type -P sed)
        export SORT=$(type -P sort)

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
    root,
    nixpkgs,
    stdenv ? pkgs.stdenv,
    uconfig ? {},
  }: let
    buildKernelConfig = pkgs.callPackage ./kernel-config.nix {
      inherit stdenv nixpkgs;
    };
    buildKernel = pkgs.callPackage ./kernel-build.nix {
      inherit stdenv;
    };
    sources = (pkgs.callPackage (import ./input.nix) {inherit nixpkgs;}) {
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
  in rec {
    kconfig = buildKernelConfig {
      inherit src version;
      kconfig = kkconfig;
    };

    kconfig-iso = buildKernelConfig {
      inherit src version;
      kconfig = kkconfig;
      iso = true;
    };

    headers = buildKernelHeaders {
      inherit src version;
    };

    kernel = buildKernel {
      inherit src kconfig version;
    };

    iso = mkIso {
      uconfig =
        {
          networking.hostName = "${name}";
          kernel = {
            inherit src version;
            kconfig = kconfig-iso.structuredConfig;
          };

          programs.xfstests = {
            arguments = "-R xunit -s xfs_4k generic/110";
            upload-results = true;
          };
        }
        // uconfig;
    };

    qcow = mkQcow {
      uconfig =
        {
          networking.hostName = "${name}";
          programs.xfstests = {
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
      inherit name root;
      uconfig =
        {
          networking.hostName = "${name}";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.sharedir = "$ROOTDIR/.kd/${name}/share";
          vm.disks = [12000 12000 2000 2000];
        }
        // uconfig;
    };

    prebuild = mkVmTest {
      inherit name root;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "${name}";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.sharedir = "$ROOTDIR/.kd/${name}/share";
          vm.disks = [12000 12000 2000 2000];

          # As our dummy derivation doesn't provide any .config we need to tell
          # NixOS not to check for any required configurations
          system.requiredKernelConfig = pkgs.lib.mkForce [];
        }
        // uconfig;
    };

    shell = mkLinuxShell {
      inherit root name;
    };
  };
}
