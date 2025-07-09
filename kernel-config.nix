{
  stdenv,
  lib,
  perl,
  gmp,
  libmpc,
  mpfr,
  bison,
  flex,
  pahole,
  nixpkgs,
}: {
  src,
  version,
  kconfig ? {},
  default ? true,
}:
stdenv.mkDerivation rec {
  inherit version src;
  pname = "linux-config";

  ignoreConfigErrors = false;
  generateConfig = nixpkgs + "/pkgs/os-specific/linux/kernel/generate-config.pl";

  kernelConfig = passthru.moduleStructuredConfig.intermediateNixConfig;
  passAsFile = ["kernelConfig"];

  depsBuildBuild = [stdenv.cc];
  nativeBuildInputs = [perl gmp libmpc mpfr bison flex pahole];

  makeFlags =
    lib.optionals (stdenv.hostPlatform.linux-kernel ? makeFlags)
    stdenv.hostPlatform.linux-kernel.makeFlags;

  postPatch = ''
    # Ensure that depmod gets resolved through PATH
    sed -i Makefile -e 's|= /sbin/depmod|= depmod|'

    # Don't include a (random) NT_GNU_BUILD_ID, to make the build more deterministic.
    # This way kernels can be bit-by-bit reproducible depending on settings
    # (e.g. MODULE_SIG and SECURITY_LOCKDOWN_LSM need to be disabled).
    # See also https://kernelnewbies.org/BuildId
    sed -i Makefile -e 's|--build-id=[^ ]*|--build-id=none|'

    # Some linux-hardened patches now remove certain files in the scripts directory, so the file may not exist.
    [[ -f scripts/ld-version.sh ]] && patchShebangs scripts/ld-version.sh

    # Set randstruct seed to a deterministic but diversified value. Note:
    # we could have instead patched gen-random-seed.sh to take input from
    # the buildFlags, but that would require also patching the kernel's
    # toplevel Makefile to add a variable export. This would be likely to
    # cause future patch conflicts.
    for file in scripts/gen-randstruct-seed.sh; do
      if [ -f "$file" ]; then
        substituteInPlace "$file" \
          --replace NIXOS_RANDSTRUCT_SEED \
          $(echo ${src} ${placeholder "configfile"} | sha256sum | cut -d ' ' -f 1 | tr -d '\n')
        break
      fi
    done

    patchShebangs scripts

    # also patch arch-specific install scripts
    for i in $(find arch -name install.sh); do
        patchShebangs "$i"
    done

    # Patch kconfig to print "###" after every question so that
    # generate-config.pl from the generic builder can answer them.
    sed -e '/fflush(stdout);/i\printf("###");' -i scripts/kconfig/conf.c
  '';

  buildPhase = ''
    export buildRoot="''${buildRoot:-build}"
    export HOSTCC=$CC_FOR_BUILD
    export HOSTCXX=$CXX_FOR_BUILD
    export HOSTAR=$AR_FOR_BUILD
    export HOSTLD=$LD_FOR_BUILD

    # Get a basic config file for later refinement with $generateConfig.
    echo "Generating 'olddefconfig' config"
    make $makeFlags \
        -C . \
        O="$buildRoot" \
        ARCH=x86_64 \
        HOSTCC=$HOSTCC \
        HOSTCXX=$HOSTCXX \
        HOSTAR=$HOSTAR \
        HOSTLD=$HOSTLD \
        CC=$CC \
        OBJCOPY=$OBJCOPY \
        OBJDUMP=$OBJDUMP \
        READELF=$READELF \
        $makeFlags \
        olddefconfig

    # Create the config file.
    echo "Generating kernel configuration"
    ln -s "$kernelConfigPath" "$buildRoot/kernel-config"
    DEBUG=1 \
      ARCH=x86_64 \
      KERNEL_CONFIG="$buildRoot/kernel-config" \
      PREFER_BUILTIN=false \
      BUILD_ROOT="$buildRoot" \
      SRC=. \
      MAKE_FLAGS="$makeFlags" \
      perl -w $generateConfig
  '';

  installPhase = "mv $buildRoot/.config $out";

  enableParallelBuilding = true;

  passthru = rec {
    # The result is a set of two attributes
    moduleStructuredConfig =
      (lib.evalModules {
        modules = [
          (nixpkgs + "/nixos/modules/system/boot/kernel_config.nix")
          (let
            configs = (import ./kconfigs/default.nix) {inherit lib;};
          in {
            settings =
              kconfig
              // (lib.optionalAttrs default configs.default);
            _file = "structuredExtraConfig";
          })
        ];
      })
        .config;

    structuredConfig = moduleStructuredConfig.settings;
  };
}
