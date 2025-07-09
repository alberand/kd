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
    uconfig,
    enableCcache,
  }:
    nixos-generators.nixosGenerate {
      inherit pkgs;
      system = "x86_64-linux";
      specialArgs = {
        diskSize = "20000";
      };
      modules = [
        (pkgs.callPackage (import ./xfstests/xfstests.nix) {
          inherit
            enableCcache
            ;
        })
        (import ./xfsprogs/module.nix {inherit enableCcache;})
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

  mkIso = {
    uconfig,
    enableCcache,
  }:
    builtins.getAttr "iso" {
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          (pkgs.callPackage (import ./xfstests/xfstests.nix) {
            inherit
              enableCcache
              ;
          })
          (import ./xfsprogs/module.nix {inherit enableCcache;})
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

  mkQcow = {
    uconfig,
    enableCcache,
  }:
    builtins.getAttr "qcow" {
      qcow = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          (pkgs.callPackage (import ./xfstests/xfstests.nix) {
            inherit
              enableCcache
              ;
          })
          (import ./xfsprogs/module.nix {inherit enableCcache;})
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
    enableCcache,
  }:
    builtins.getAttr "runner" rec {
      inherit name root;
      nixos = mkVM {
        inherit uconfig enableCcache;
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
          # TODO this has to be proper name
          ${nixos}/bin/run-*-vm 2>&1 | tee -a $LOG_FILE
          echo "View results at $RUNDIR/results"
          echo "Log is in $LOG_FILE"
        '';
    };

  mkLinuxShell = {
    root,
    name,
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
              qemu_full
              qemu-utils
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

          NODE_NAME = "${name}";
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
    root,
    nixpkgs,
    pkgs,
    stdenv ? pkgs.stdenv,
    uconfig ? {},
    enableCcache ? false,
  }: let
    buildKernelConfig = pkgs.callPackage ./kernel-config.nix {
      inherit stdenv nixpkgs;
    };
    buildKernel = pkgs.callPackage ./kernel-build.nix {
      inherit stdenv enableCcache;
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
    inherit (pkgs) xfsprogs;

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
      inherit enableCcache;
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
      inherit enableCcache;
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
      inherit name root enableCcache;
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
      inherit name root enableCcache;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "${name}-prebuild";
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

    kgdbvm = mkVmTest {
      inherit name root enableCcache;
      uconfig =
        {
          # Same as in .vm
          networking.hostName = "${name}-kgdb";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.sharedir = "$ROOTDIR/.kd/${name}/share";
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

    initrd = let
      dummy-system = let
        nixosGenerate = {
          pkgs ? null,
          lib ? nixpkgs.lib,
          nixosSystem ? nixpkgs.lib.nixosSystem,
          format,
          system ? null,
          specialArgs ? {},
          modules ? [],
          customFormats ? {},
        }: let
          extraFormats =
            lib.mapAttrs' (
              name: value:
                lib.nameValuePair
                name
                {
                  imports = [
                    value
                    (nixos-generators + /format-module.nix)
                  ];
                }
            )
            customFormats;
          formatModule = builtins.getAttr format (nixos-generators.nixosModules // extraFormats);
          image = nixosSystem {
            inherit pkgs specialArgs;
            system =
              if system != null
              then system
              else pkgs.system;
            lib =
              if lib != null
              then lib
              else pkgs.lib;
            modules =
              [
                formatModule
              ]
              ++ modules;
          };
        in
          image;
      in
        nixosGenerate {
          inherit pkgs;
          system = "x86_64-linux";
          specialArgs = {
            diskSize = "20000";
          };
          modules = [
            ./xfstests/xfstests.nix
            ./xfsprogs/module.nix
            ./dummy.nix
            ./system.nix
            ./vm.nix
            (pkgs.callPackage (import ./input.nix) {inherit nixpkgs;})
            ({...}: uconfig)
          ];
          format = "vm";
        };
      config = dummy-system.config;

      modulesClosure = pkgs.makeModulesClosure {
        rootModules = config.boot.initrd.availableKernelModules ++ config.boot.initrd.kernelModules;
        kernel = config.system.modulesTree;
        firmware = config.hardware.firmware;
        allowMissing = false;
      };

      udev = config.systemd.package;

      utils = pkgs.callPackage (import (nixpkgs + /nixos/lib/utils.nix)) {};

      # The initrd only has to mount `/` or any FS marked as necessary for
      # booting (such as the FS containing `/nix/store`, or an FS needed for
      # mounting `/`, like `/` on a loopback).
      fileSystems = pkgs.lib.filter utils.fsNeededForBoot config.system.build.fileSystems;

      # A utility for enumerating the shared-library dependencies of a program
      findLibs = pkgs.buildPackages.writeShellScriptBin "find-libs" ''
        set -euo pipefail

        declare -A seen
        left=()

        patchelf="${pkgs.buildPackages.patchelf}/bin/patchelf"

        function add_needed {
          rpath="$($patchelf --print-rpath $1)"
          dir="$(dirname $1)"
          for lib in $($patchelf --print-needed $1); do
            left+=("$lib" "$rpath" "$dir")
          done
        }

        add_needed "$1"

        while [ ''${#left[@]} -ne 0 ]; do
          next=''${left[0]}
          rpath=''${left[1]}
          ORIGIN=''${left[2]}
          left=("''${left[@]:3}")
          if [ -z ''${seen[$next]+x} ]; then
            seen[$next]=1

            # Ignore the dynamic linker which for some reason appears as a DT_NEEDED of glibc but isn't in glibc's RPATH.
            case "$next" in
              ld*.so.?) continue;;
            esac

            IFS=: read -ra paths <<< $rpath
            res=
            for path in "''${paths[@]}"; do
              path=$(eval "echo $path")
              if [ -f "$path/$next" ]; then
                  res="$path/$next"
                  echo "$res"
                  add_needed "$res"
                  break
              fi
            done
            if [ -z "$res" ]; then
              echo "Couldn't satisfy dependency $next" >&2
              exit 1
            fi
          fi
        done
      '';

      # Some additional utilities needed in stage 1, like mount, lvm, fsck
      # etc.  We don't want to bring in all of those packages, so we just
      # copy what we need.  Instead of using statically linked binaries,
      # we just copy what we need from Glibc and use patchelf to make it
      # work.
      extraUtils =
        pkgs.runCommand "extra-utils"
        {
          nativeBuildInputs = with pkgs.buildPackages; [
            nukeReferences
            bintools
          ];
          allowedReferences = ["out"]; # prevent accidents like glibc being included in the initrd
        }
        ''
          set +o pipefail

          mkdir -p $out/bin $out/lib
          ln -s $out/bin $out/sbin

          copy_bin_and_libs () {
            [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
            cp -pdv $1 $out/bin
          }

          # Copy BusyBox.
          for BIN in ${pkgs.busybox}/{s,}bin/*; do
            copy_bin_and_libs $BIN
          done

          # Copy some util-linux stuff.
          copy_bin_and_libs ${pkgs.util-linux}/sbin/blkid

          # Copy dmsetup and lvm.
          copy_bin_and_libs ${pkgs.lib.getBin pkgs.lvm2}/bin/dmsetup
          copy_bin_and_libs ${pkgs.lib.getBin pkgs.lvm2}/bin/lvm

          # Copy udev.
          copy_bin_and_libs ${udev}/bin/udevadm
          cp ${pkgs.lib.getLib udev.kmod}/lib/libkmod.so* $out/lib
          copy_bin_and_libs ${udev}/lib/systemd/systemd-sysctl
          for BIN in ${udev}/lib/udev/*_id; do
            copy_bin_and_libs $BIN
          done
          # systemd-udevd is only a symlink to udevadm these days
          ln -sf udevadm $out/bin/systemd-udevd

          # Copy modprobe.
          copy_bin_and_libs ${pkgs.kmod}/bin/kmod
          ln -sf kmod $out/bin/modprobe

          ${config.boot.initrd.extraUtilsCommands}

          # Copy ld manually since it isn't detected correctly
          cp -pv ${pkgs.stdenv.cc.libc.out}/lib/ld*.so.? $out/lib

          # Copy all of the needed libraries in a consistent order so
          # duplicates are resolved the same way.
          find $out/bin $out/lib -type f | sort | while read BIN; do
            echo "Copying libs for executable $BIN"
            for LIB in $(${findLibs}/bin/find-libs $BIN); do
              TGT="$out/lib/$(basename $LIB)"
              if [ ! -f "$TGT" ]; then
                SRC="$(readlink -e $LIB)"
                cp -pdv "$SRC" "$TGT"
              fi
            done
          done

          # Strip binaries further than normal.
          chmod -R u+w $out
          stripDirs "$STRIP" "$RANLIB" "lib bin" "-s"

          # Run patchelf to make the programs refer to the copied libraries.
          find $out/bin $out/lib -type f | while read i; do
            nuke-refs -e $out $i
          done

          find $out/bin -type f | while read i; do
            echo "patching $i..."
            patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
          done

          find $out/lib -type f \! -name 'ld*.so.?' | while read i; do
            echo "patching $i..."
            patchelf --set-rpath $out/lib $i
          done

          if [ -z "${toString (pkgs.stdenv.hostPlatform != pkgs.stdenv.buildPlatform)}" ]; then
          # Make sure that the patchelf'ed binaries still work.
          echo "testing patched programs..."
          $out/bin/ash -c 'echo hello world' | grep "hello world"
          $out/bin/mount --help 2>&1 | grep -q "BusyBox"
          $out/bin/blkid -V 2>&1 | grep -q 'libblkid'
          $out/bin/udevadm --version
          $out/bin/dmsetup --version 2>&1 | tee -a log | grep -q "version:"
          LVM_SYSTEM_DIR=$out $out/bin/lvm version 2>&1 | tee -a log | grep -q "LVM"
          ${config.boot.initrd.extraUtilsCommandsTest}
          fi
        ''; # */

      # Networkd link files are used early by udev to set up interfaces early.
      # This must be done in stage 1 to avoid race conditions between udev and
      # network daemons.
      linkUnits =
        pkgs.runCommand "link-units"
        {
          allowedReferences = [extraUtils];
          preferLocalBuild = true;
        }
        (
          ''
            mkdir -p $out
            cp -v ${udev}/lib/systemd/network/*.link $out/
          ''
          + (
            let
              links = pkgs.lib.filterAttrs (n: v: pkgs.lib.hasSuffix ".link" n) config.systemd.network.units;
              files = pkgs.lib.mapAttrsToList (n: v: "${v.unit}/${n}") links;
            in
              pkgs.lib.concatMapStringsSep "\n" (file: "cp -v ${file} $out/") files
          )
        );

      udevRules =
        pkgs.runCommand "udev-rules"
        {
          allowedReferences = [extraUtils];
          preferLocalBuild = true;
        }
        ''
          mkdir -p $out

          cp -v ${udev}/lib/udev/rules.d/60-cdrom_id.rules $out/
          cp -v ${udev}/lib/udev/rules.d/60-persistent-storage.rules $out/
          cp -v ${udev}/lib/udev/rules.d/75-net-description.rules $out/
          cp -v ${udev}/lib/udev/rules.d/80-drivers.rules $out/
          cp -v ${udev}/lib/udev/rules.d/80-net-setup-link.rules $out/
          cp -v ${pkgs.lvm2}/lib/udev/rules.d/*.rules $out/
          ${config.boot.initrd.extraUdevRulesCommands}

          for i in $out/*.rules; do
              substituteInPlace $i \
                --replace ata_id ${extraUtils}/bin/ata_id \
                --replace scsi_id ${extraUtils}/bin/scsi_id \
                --replace cdrom_id ${extraUtils}/bin/cdrom_id \
                --replace ${pkgs.coreutils}/bin/basename ${extraUtils}/bin/basename \
                --replace ${pkgs.util-linux}/bin/blkid ${extraUtils}/bin/blkid \
                --replace ${pkgs.lib.getBin pkgs.lvm2}/bin ${extraUtils}/bin \
                --replace ${pkgs.mdadm}/sbin ${extraUtils}/sbin \
                --replace ${pkgs.bash}/bin/sh ${extraUtils}/bin/sh \
                --replace ${udev} ${extraUtils}
          done

          # Work around a bug in QEMU, which doesn't implement the "READ
          # DISC INFORMATION" SCSI command:
          #   https://bugzilla.redhat.com/show_bug.cgi?id=609049
          # As a result, `cdrom_id' doesn't print
          # ID_CDROM_MEDIA_TRACK_COUNT_DATA, which in turn prevents the
          # /dev/disk/by-label symlinks from being created.  We need these
          # in the NixOS installation CD, so use ID_CDROM_MEDIA in the
          # corresponding udev rules for now.  This was the behaviour in
          # udev <= 154.  See also
          #   https://www.spinics.net/lists/hotplug/msg03935.html
          substituteInPlace $out/60-persistent-storage.rules \
            --replace ID_CDROM_MEDIA_TRACK_COUNT_DATA ID_CDROM_MEDIA
        ''; # */

      bootStage1 = pkgs.replaceVarsWith {
        src = nixpkgs + /nixos/modules/system/boot/stage-1-init.sh;
        isExecutable = true;

        postInstall = ''
          echo checking syntax
          # check both with bash
          ${pkgs.buildPackages.bash}/bin/sh -n $target
          # and with ash shell, just in case
          ${pkgs.buildPackages.busybox}/bin/ash -n $target
        '';

        replacements = {
          shell = "${extraUtils}/bin/ash";

          inherit linkUnits udevRules extraUtils;

          inherit (config.boot) resumeDevice;

          inherit (config.system.nixos) distroName;

          inherit (config.system.build) earlyMountScript;

          inherit
            (config.boot.initrd)
            checkJournalingFS
            verbose
            preLVMCommands
            preDeviceCommands
            postDeviceCommands
            postResumeCommands
            postMountCommands
            preFailCommands
            kernelModules
            ;

          resumeDevices = map (sd:
            if sd ? device
            then sd.device
            else "/dev/disk/by-label/${sd.label}") (
            pkgs.lib.filter (
              sd:
                pkgs.lib.hasPrefix "/dev/" sd.device
                && !sd.randomEncryption.enable
                # Don't include zram devices
                && !(pkgs.lib.hasPrefix "/dev/zram" sd.device)
            )
            config.swapDevices
          );

          fsInfo = let
            f = fs: [
              fs.mountPoint
              (
                if fs.device != null
                then fs.device
                else "/dev/disk/by-label/${fs.label}"
              )
              fs.fsType
              (builtins.concatStringsSep "," fs.options)
            ];
          in
            pkgs.writeText "initrd-fsinfo" (pkgs.lib.concatStringsSep "\n" (pkgs.lib.concatMap f fileSystems));

          setHostId = pkgs.lib.optionalString (config.networking.hostId != null) ''
            hi="${config.networking.hostId}"
            ${
              if pkgs.stdenv.hostPlatform.isBigEndian
              then ''
                echo -ne "\x''${hi:0:2}\x''${hi:2:2}\x''${hi:4:2}\x''${hi:6:2}" > /etc/hostid
              ''
              else ''
                echo -ne "\x''${hi:6:2}\x''${hi:4:2}\x''${hi:2:2}\x''${hi:0:2}" > /etc/hostid
              ''
            }
          '';
        };
      };
    in
      pkgs.callPackage (import (nixpkgs + /pkgs/build-support/kernel/make-initrd.nix)) {
        name = "initrd-kd";

        contents = [
          {
            object = bootStage1;
            symlink = "/init";
          }
        ];
      };

    shell = mkLinuxShell {
      inherit root name;
    };

    shell-clang20 = mkLinuxShell {
      inherit root name;
      clangVersion = "20";
    };

    shell-clang18 = mkLinuxShell {
      inherit root name;
      clangVersion = "18";
    };

    shell-clang17 = mkLinuxShell {
      inherit root name;
      clangVersion = "17";
    };

    shell-gcc = mkLinuxShell {
      inherit root name;
      gcc = true;
    };

    shell-gcc15 = mkLinuxShell {
      inherit root name;
      gcc = true;
      gccVersion = "15";
    };

    shell-gcc14 = mkLinuxShell {
      inherit root name;
      gcc = true;
      gccVersion = "14";
    };

    shell-gcc13 = mkLinuxShell {
      inherit root name;
      gcc = true;
      gccVersion = "13";
    };
  };
}
