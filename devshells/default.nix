{pkgs}: let
  mkLlvmPkgs = {clangVersion}: let
    llvmPackages =
      if clangVersion != ""
      then pkgs."llvmPackages_${clangVersion}"
      else pkgs.llvmPackages;
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

  # ccache-wrapped compiler matching the shell's toolchain. ccache is bundled
  # from the Nix store (no system install needed); the wrapper masquerades as
  # cc/gcc/clang so that `make` picks it up automatically.
  mkCcacheCC = {
    clangVersion ? "",
    gcc ? false,
    gccVersion ? "",
  }:
    if gcc
    then
      (
        if gccVersion != ""
        then pkgs.ccacheStdenv.override {stdenv = pkgs."gcc${gccVersion}Stdenv";}
        else pkgs.ccacheStdenv
      )
      .cc
    else
      (pkgs.ccacheStdenv.override {
        inherit
          (
            if clangVersion != ""
            then pkgs."llvmPackages_${clangVersion}"
            else pkgs.llvmPackages
          )
          stdenv
          ;
      })
      .cc;

  mkLinuxShell = {
    clangVersion ? "",
    gcc ? false,
    gccVersion ? "",
    packages ? [],
    sources ? {},
  }: let
    ccacheCC = mkCcacheCC {inherit clangVersion gcc gccVersion;};
  in
    builtins.getAttr "shell" {
      shell = pkgs.mkShell (
        {
          packages = with pkgs;
            [
              # Keep first so its cc/gcc/clang win on PATH over the plain
              # compiler, routing all compiles through ccache.
              ccacheCC
              # ccache CLI itself, for `ccache -s` and the banner below.
              ccache
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
              lld
              gettext
              libtool
              automake
              autoconf
              pahole
              trace-cmd
              b4
              patchutils_0_4_2
              vmtest-deploy
              kd
              elfutils
              openssl
              zlib
              smatch
            ]
            ++ (
              if gcc
              then (mkGccPkgs {inherit gccVersion;})
              else (mkLlvmPkgs {inherit clangVersion;})
            )
            ++ packages;

          LD_LIBRARY_PATH = "${pkgs.lib.makeLibraryPath (
            with pkgs; [
              ncurses
              elfutils
              openssl
              zlib
            ]
          )}";

          KBUILD_BUILD_TIMESTAMP = "";
          # Disable all automatically applied hardening. The Linux
          # kernel will take care of itself.
          NIX_HARDENING_ENABLE = "";
          SOURCE_DATE_EPOCH = 0;
          CCACHE_MAXSIZE = "25G";
          # random_seed is required for kernel builds (randstruct /
          # -frandom-seed), otherwise ccache misses on every object.
          CCACHE_SLOPPINESS = "random_seed";
          CCACHE_UMASK = 007;
          # Depend mode: skip preprocessing by using the kernel's -MD deps,
          # speeding up both hits and misses.
          CCACHE_DEPEND = "1";
          # Retrieve hits via CoW reflinks (near-free on btrfs/xfs); falls back
          # to copying on filesystems without reflink support. Not hardlink:
          # objtool/modpost rewrite .o files in place and would corrupt the cache.
          CCACHE_FILECLONE = "1";

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
            # Expand $HOME (mkShell attrs are not expanded) and let an existing
            # CCACHE_DIR / ~/.config/ccache/ccache.conf take precedence.
            export CCACHE_DIR="''${CCACHE_DIR:-$HOME/.cache/ccache}"

            echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
            echo "Envrionment has:"
            echo -e "\tkernel: ${sources.options.kernel.version.default}"
            echo -e "\txfsprogs: ${xfsprogs-version}"
            echo -e "\txfstests: ${xfstests-version}"
            echo -e "\tccache: $(ccache --version | head -n1) ($CCACHE_DIR)"
          '';
        }
        // (pkgs.lib.optionalAttrs (!gcc) {
          LLVM = 1;
          # Fix '-nostdlibinc' preventing linux kernel compilation in the
          # devshell. TODO This should be properly fixed upstream (should this
          # flag be added at all???). Or better workaround would be to override
          # this in llvmPackages.
          # https://github.com/NixOS/nixpkgs/issues/368850
          # https://github.com/NixOS/nixpkgs/pull/191152
          # Fix `--target` spam.
          NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = 1;
          # Fix `-nostdinc` warnings.
          NIX_CFLAGS_COMPILE = "-Wno-unused-command-line-argument";
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
    packages = with pkgs; [
      # Keep first so its cc/clang win on PATH, routing compiles through ccache.
      (mkCcacheCC {clangVersion = "19";})
      ccache
      gitFull
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
      kd
      (mkLlvmPkgs {clangVersion = "19";})
    ];

    KBUILD_BUILD_TIMESTAMP = "";
    SOURCE_DATE_EPOCH = 0;
    CCACHE_SLOPPINESS = "random_seed";
    CCACHE_UMASK = 007;
    CCACHE_DEPEND = "1";
    CCACHE_FILECLONE = "1";

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
      export CCACHE_DIR="''${CCACHE_DIR:-$HOME/.cache/ccache}"
      echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
    '';
  };
  xfstests = pkgs.mkShell {
    packages = with pkgs; [
      # Keep first so its cc/clang win on PATH, routing compiles through ccache.
      (mkCcacheCC {clangVersion = "19";})
      ccache
      gitFull
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
      kd
      (mkLlvmPkgs {clangVersion = "19";})
    ];

    KBUILD_BUILD_TIMESTAMP = "";
    SOURCE_DATE_EPOCH = 0;
    CCACHE_SLOPPINESS = "random_seed";
    CCACHE_UMASK = 007;
    CCACHE_DEPEND = "1";
    CCACHE_FILECLONE = "1";

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
      export CCACHE_DIR="''${CCACHE_DIR:-$HOME/.cache/ccache}"
      echo "$(tput setaf 166)Welcome to $(tput setaf 227)kd$(tput setaf 166) shell.$(tput sgr0)"
    '';
  };

  xfsdump = pkgs.mkShell {
    packages = with pkgs; [
      gitFull
      acl
      attr
      automake
      autoconf
      libtool
      libuuid
      ncurses
      libxfs
      kd
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

  dev = pkgs.mkShell {
    packages = with pkgs; [
      gitFull
      cargo
      rustc
      pkg-config
      openssl
      rust-analyzer
      rustfmt
      cachix
    ];
  };

  default = shell;
}
