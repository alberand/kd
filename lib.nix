{
  pkgs,
  nixos-generators,
  nixpkgs,
}: rec {

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
          programs.xfsprogs.enable = true;
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
          ({
            pkgs,
            ...
          }: {
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

  mkVmTest = {uconfig}:
    builtins.getAttr "vmtest" rec {
      nixos = mkVM {
        inherit uconfig;
      };

      vmtest =
        pkgs.writeScriptBin "kd-run-vm"
        ((builtins.readFile ./run.sh)
          + ''
            ${nixos}/bin/run-$NODE_NAME-vm 2>&1 | tee -a $LOG_FILE
            echo "View results at $SHARE_DIR/results"
            echo "Log is in $LOG_FILE"
          '');
    };

  mkLinuxShell = {
    root,
    name,
    sharedir ? "/tmp/vmtest",
    packages ? [],
  }:
    builtins.getAttr "shell" {
      shell = pkgs.mkShell {
        nativeBuildInputs = with pkgs;
          [
            ctags
            getopt
            flex
            bison
            perl
            gnumake
            bc
            jq
            pkg-config
            clang
            clang-tools
            lld
            file
            gettext
            libtool
            qemu_full
            qemu-utils
            automake
            autoconf
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
            pahole
            sphinx # for btrfs-progs
            zstd # for btrfs-progs
            udev # for btrfs-progs
            lzo # for btrfs-progs
            liburing # for btrfs-progs
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

            # kselftest deps
            libcap
            libcap_ng
            fuse3
            fuse
            alsa-lib
            libmnl
            numactl
            (smatch.overrideAttrs (final: prev: {
              version = "git";
              src = fetchgit {
                url = "git://repo.or.cz/smatch.git";
                rev = "b8540ba87345cda269ef4490dd533aa6e8fb9229";
                hash = "sha256-LQhNwhSbEP3BjBrT3OFjOjAoJQ1MU0HhyuBQPffOO48=";
              };
            }))

            python312
            python312Packages.flake8
            python312Packages.pylint
            cargo
            rustc

            (
              let
                name = "vmtest";
                vmtest = (pkgs.writeScriptBin name (builtins.readFile ./vmtest.sh)).overrideAttrs (old: {
                  buildCommand = ''
                    ${old.buildCommand}
                    patchShebangs $out
                    substituteInPlace $out/bin/${name} \
                      --subst-var-by root ${root}
                  '';
                });
              in
                pkgs.symlinkJoin {
                  name = name;
                  paths = [vmtest];
                  buildInputs = [pkgs.makeWrapper];
                  postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
                }
            )
            (vmtest-deploy {})

            # vmtest deps
            nurl
            nixfmt-classic

            (callPackage (import ./kd/derivation.nix) {})
          ]
          ++ packages
          ++ [
            # xfsprogs
            icu
            libuuid # codegen tool uses libuuid
            liburcu # required by crc32selftest
            readline
            inih
          ]
          ++ [
            # xfstests
            gawk
            libuuid
            libxfs
            gdbm
          ];

        buildInputs = with pkgs; [
          elfutils
          ncurses
          openssl
          zlib
        ];

        SHARE_DIR = "${sharedir}";
        NODE_NAME = "${name}";
        KBUILD_BUILD_TIMESTAMP = "";
        SOURCE_DATE_EPOCH = 0;
        CCACHE_DIR = "/var/cache/ccache/";
        CCACHE_SLOPPINESS = "random_seed";
        CCACHE_UMASK = 777;

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

    vm = mkVmTest {
      uconfig =
        {
          networking.hostName = "${name}";
          kernel = {
            inherit src version;
            kconfig = kkconfig;
          };
          vm.disks = [12000 12000 2000 2000];
        }
        // uconfig;
    };

    shell = mkLinuxShell {
      inherit root name;
    };
  };
}
