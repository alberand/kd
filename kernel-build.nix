{
  pkgs,
  stdenv,
  ccacheStdenv,
  lib,
}: {
  src,
  kconfig,
  version,
}:
(pkgs.linuxManualConfig
  {
    inherit src version  lib;
    configfile = kconfig;
    allowImportFromDerivation = true;
    # We always want to use ccacheStdenv. By if we do stdenv = ccacheStdenv it
    # will always use gcc. So, if stdenv is llvm fix ccacheStdenv.
    stdenv =
      if stdenv.cc.isClang
      then
        pkgs.ccacheStdenv.override {
          inherit (pkgs.llvmPackages_latest) stdenv;
        }
      else ccacheStdenv;
  })
.overrideAttrs (old: {
  nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.cpio];
  dontStrip = true;
  patches = [
    ./randstruct-provide-seed.patch
  ];
  # Temporary fix for the following
  # clang: error: argument unused during compilation: '-fno-strict-overflow' [-Werror,-Wunused-command-line-argument]
  hardeningDisable = lib.optional stdenv.cc.isClang "strictoverflow";
  preConfigure = ''
    export CCACHE_MAXSIZE=5G
    export CCACHE_DIR=/var/cache/ccache/
    export CCACHE_SLOPPINESS=random_seed
    export CCACHE_UMASK=666
    export KBUILD_BUILD_TIMESTAMP=""
  '';
})
