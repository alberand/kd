{pkgs}: let
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

  vmtest-deploy = (
    builtins.getAttr "script" {
      script = pkgs.writeScriptBin "vmtest-deploy" (builtins.readFile ../deploy.sh);
    }
  );

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
              vmtest-deploy

              (callPackage (import ../kd/derivation.nix) {
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

          MAKE = "${pkgs.gnumake}/bin/make";
          SORT = "${pkgs.coreutils}/bin/sort";
          SED = "${pkgs.gnused}/bin/sed";
          AWK = "${pkgs.gawk}/bin/awk";
          MSGFMT = "${pkgs.gettext}/bin/msgfmt";
          MSGMERGE = "${pkgs.gettext}/bin/msgmerge";
          XGETTEXT = "${pkgs.gettext}/bin/xgettext";
          TAR = "${pkgs.gnutar}/bin/tar";
          ZIP = "${pkgs.gzip}/bin/gzip";
          RPM = "${pkgs.rpm}/bin/rpm";
          LIBTOOL = "${pkgs.libtool}/bin/libtool";

          shellHook = let
            xfsprogs-version = (pkgs.lib.importJSON ../sources/xfsprogs.json).rev;
            xfstests-version = (pkgs.lib.importJSON ../sources/xfstests.json).rev;
          in ''
            export MAKEFLAGS="-j$(nproc)"

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

  sources = (import ../input.nix) {
    inherit pkgs;
    config = {};
  };
in rec {
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

  xfsprogs = pkgs.mkShell {
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

    MAKE = "${pkgs.gnumake}/bin/make";
    SORT = "${pkgs.coreutils}/bin/sort";
    SED = "${pkgs.gnused}/bin/sed";
    AWK = "${pkgs.gawk}/bin/awk";
    MSGFMT = "${pkgs.gettext}/bin/msgfmt";
    MSGMERGE = "${pkgs.gettext}/bin/msgmerge";
    XGETTEXT = "${pkgs.gettext}/bin/xgettext";
    TAR = "${pkgs.gnutar}/bin/tar";
    ZIP = "${pkgs.gzip}/bin/gzip";
    RPM = "${pkgs.rpm}/bin/rpm";

    shellHook = ''
      export MAKEFLAGS="-j$(nproc)"
      echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
    '';
  };
  xfstests = pkgs.mkShell {
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

    MAKE = "${pkgs.gnumake}/bin/make";
    SORT = "${pkgs.coreutils}/bin/sort";
    SED = "${pkgs.gnused}/bin/sed";
    AWK = "${pkgs.gawk}/bin/awk";
    MSGFMT = "${pkgs.gettext}/bin/msgfmt";
    MSGMERGE = "${pkgs.gettext}/bin/msgmerge";
    XGETTEXT = "${pkgs.gettext}/bin/xgettext";
    TAR = "${pkgs.gnutar}/bin/tar";
    ZIP = "${pkgs.gzip}/bin/gzip";
    RPM = "${pkgs.rpm}/bin/rpm";

    shellHook = ''
      export MAKEFLAGS="-j$(nproc)"
      echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
    '';
  };

  xfsdump = pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      acl
      attr
      automake
      autoconf
      libtool
      libuuid
      ncurses
      libxfs
      (mkLlvmPkgs {clangVersion = "19";})
    ];

    MAKEFLAGS = "-j$(nproc)";
    MAKE = "${pkgs.gnumake}/bin/make";
    SORT = "${pkgs.coreutils}/bin/sort";
    SED = "${pkgs.gnused}/bin/sed";
    AWK = "${pkgs.gawk}/bin/awk";
    MSGFMT = "${pkgs.gettext}/bin/msgfmt";
    MSGMERGE = "${pkgs.gettext}/bin/msgmerge";
    XGETTEXT = "${pkgs.gettext}/bin/xgettext";
    TAR = "${pkgs.gnutar}/bin/tar";
    ZIP = "${pkgs.gzip}/bin/gzip";
    RPM = "${pkgs.rpm}/bin/rpm";

    shellHook = ''
      echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd-xfsdump$(tput setaf 166) shell.$(tput sgr0)"
    '';
  };
  xfsrestore = xfsdump;

  kd-dev = pkgs.mkShell {
    buildInputs = with pkgs; [
      cargo
      rustc
      pkg-config
      openssl
      rust-analyzer
      rustfmt
    ];
  };

  default = shell;
}
