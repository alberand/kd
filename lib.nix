{
  pkgs,
  nixos-generators,
  nixpkgs,
  ...
}: rec {
  mkVM = {
    pkgs,
    sharedir,
    qemu-options ? [],
    user-config ? {},
  }:
    nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      specialArgs = {diskSize = "20000";};
      modules = let
        xfstests = import ./xfstests/configs.nix;
      in [
        ./xfstests/xfstests.nix
        ./xfsprogs.nix
        ./simple-test.nix
        ./system.nix
        ./vm.nix
        ({...}: user-config)
        ({...}: {
          programs.simple-test = {
            enable = true;
          };
          programs.xfstests = {
            enable = true;
            testconfig = pkgs.lib.mkDefault xfstests.xfstests-all;
            test-dev = pkgs.lib.mkDefault "/dev/vdb";
            scratch-dev = pkgs.lib.mkDefault "/dev/vdc";
          };
        })
      ];
      format = "vm";
    };

  mkIso = {
    pkgs,
    test-disk,
    scratch-disk,
    user-config ? {},
  }:
    builtins.getAttr "iso" {
      iso = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        modules = [
          ./xfstests/xfstests.nix
          ./xfsprogs.nix
          ./system.nix
          ({
            config,
            pkgs,
            ...
          }:
            {
              # Don't shutdown system as libvirtd will remove the VM
              programs.xfstests.autoshutdown = false;

              networking.networkmanager.enable = true;

              fileSystems."/mnt/test" = {
                device = test-disk;
                fsType = "xfs";
                autoFormat = true;
              };

              fileSystems."/mnt/scratch" = {
                device = scratch-disk;
                fsType = "xfs";
                autoFormat = true;
              };
            }
            // user-config)
        ];
        format = "iso";
      };
    };

  mkVmTest = {
    pkgs,
    sharedir ? "/tmp/vmtest",
    qemu-options ? [],
    user-config ? {},
  }:
    builtins.getAttr "vmtest" rec {
      nixos = mkVM {
        inherit pkgs sharedir qemu-options user-config;
      };

      vmtest =
        pkgs.writeScriptBin "vmtest"
        ((builtins.readFile ./run.sh)
          + ''
            ${nixos}/bin/run-$NODE_NAME-vm 2>&1 | tee -a $LOG_FILE
            echo "View results at $SHARE_DIR/results"
            echo "Log is in $LOG_FILE"
          '');
    };

  mkLinuxShell = {
    pkgs,
    root,
    sharedir ? "/tmp/vmtest",
    packages ? [],
    name ? "vmtest",
    pname ? "vmtest",
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
            (vmtest-deploy {inherit pkgs;})
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
          ];

        buildInputs = with pkgs; [
          elfutils
          ncurses
          openssl
          zlib
        ];

        SHARE_DIR = "${sharedir}";
        NODE_NAME = "${name}";
        PNAME = "${pname}";

        shellHook = ''
          curdir="$(pwd)"
          if [ ! -f "$curdir/compile_commands.json" ] &&
              [ -f "$curdir/scripts/clang-tools/gen_compile_commands.py" ]; then
            "$curdir/scripts/clang-tools/gen_compile_commands.py"
          fi

          if type -p ccache; then
            export KBUILD_BUILD_TIMESTAMP=""
            alias make='make CC="ccache gcc"'
          fi

          export AWK=$(type -P awk)
          export ECHO=$(type -P echo)
          export LIBTOOL=$(type -P libtool)
          export MAKE=$(type -P make)
          export SED=$(type -P sed)
          export SORT=$(type -P sort)
        '';
      };
    };

  buildKernelConfig = pkgs.callPackage ./kernel-config.nix {};
  buildKernel = pkgs.callPackage ./kernel-build.nix {};

  vmtest-deploy = {pkgs}:
    builtins.getAttr "script" {
      script = pkgs.writeScriptBin "vmtest-deploy" (builtins.readFile ./deploy.sh);
    };
}
