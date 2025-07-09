{
  pkgs,
  stdenv,
  ccacheStdenv,
  lib,
  enableCcache ? false,
}: {
  src,
  kconfig,
  version,
}:
(pkgs.linuxManualConfig
  {
    inherit src version lib;
    configfile = kconfig;
    allowImportFromDerivation = true;
    # Standard lib.versions.pad doesn't handle 'v' in front let's define our own
    # TODO suggest it upstream?
    modDirVersion = let
      pad = n: version: let
        numericVersion =
          lib.head (lib.splitString "-"
            version);
        versionSuffix = lib.removePrefix numericVersion version;
        prefixlessVersion = lib.removePrefix "v" numericVersion;
      in
        lib.concatStringsSep "." (lib.take n (lib.splitVersion prefixlessVersion
            ++ lib.genList (_: "0") n))
        + versionSuffix;
    in (pad 3 version);
  }
  // lib.optionalAttrs enableCcache {
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
.overrideAttrs (old:
    {
      nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.cpio];
      dontStrip = true;
      patches = [
        ./randstruct-provide-seed.patch
      ];
      # Temporary fix for the following
      # clang: error: argument unused during compilation: '-fno-strict-overflow' [-Werror,-Wunused-command-line-argument]
      hardeningDisable = lib.optional stdenv.cc.isClang "strictoverflow";
    }
    // lib.optionalAttrs enableCcache {
      preConfigure = ''
        export CCACHE_MAXSIZE=5G
        export CCACHE_DIR=/var/cache/ccache/
        export CCACHE_SLOPPINESS=random_seed
        export CCACHE_UMASK=007
        export KBUILD_BUILD_TIMESTAMP=""
      '';
    })
