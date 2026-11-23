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
  buildPackages,
  writeText,
  kconfigs,
  path,
}: {
  src,
  version,
  kconfig ? {},
  default ? true,
}:
stdenv.mkDerivation rec {
  inherit version src;
  pname = "linux-config";

  # kd keeps auto-module selection disabled: every option sticks to its
  # defconfig/explicit value instead of being turned into a module.
  autoModules = false;
  preferBuiltin = false;
  kernelArch = stdenv.hostPlatform.linuxArch;

  generateConfig = path + "/pkgs/os-specific/linux/kernel/generate-config.pl";

  depsBuildBuild = [buildPackages.stdenv.cc];
  nativeBuildInputs = [perl gmp libmpc mpfr bison flex pahole];

  # These are read from the environment by generate-config.pl. With
  # __structuredAttrs enabled, plain attributes are not exported to the
  # environment, so they have to go through `env`.
  env = {
    # kd does not build the kernel with Rust support.
    RUST_LIB_SRC = "";
    ignoreConfigErrors = false;
  };

  makeFlags = import (path + "/pkgs/os-specific/linux/kernel/common-flags.nix") {
    inherit lib stdenv buildPackages;
  };

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

  buildPhase = let
    kernelIntermediateConfig =
      writeText "kernel-intermediate-config"
      passthru.moduleStructuredConfig.intermediateNixConfig;
  in
    ''
      export buildRoot="''${buildRoot:-build}"

      # Get a basic config file for later refinement with $generateConfig.
      make "''${makeFlags[@]}" \
          -C . O="$buildRoot" defconfig \
          ARCH=$kernelArch CROSS_COMPILE=${stdenv.cc.targetPrefix} \

      # Create the config file.
      echo "generating kernel configuration..."
      ln -s "${kernelIntermediateConfig}" "$buildRoot/kernel-config"
      DEBUG=1 ARCH=$kernelArch CROSS_COMPILE=${stdenv.cc.targetPrefix} \
        KERNEL_CONFIG="$buildRoot/kernel-config" AUTO_MODULES=$autoModules \
        PREFER_BUILTIN=$preferBuiltin BUILD_ROOT="$buildRoot" SRC=. MAKE_FLAGS="''${makeFlags[*]@Q}" \
        perl -w $generateConfig
    ''
    + lib.optionalString stdenv.cc.isClang ''
      if ! grep -Fq CONFIG_CC_IS_CLANG=y $buildRoot/.config; then
        echo "Kernel config didn't recognize the clang compiler?"
        exit 1
      fi
    ''
    + lib.optionalString stdenv.cc.bintools.isLLVM ''
      if ! grep -Fq CONFIG_LD_IS_LLD=y $buildRoot/.config; then
        echo "Kernel config didn't recognize the LLVM linker?"
        exit 1
      fi
    '';

  installPhase = "mv $buildRoot/.config $out";

  enableParallelBuilding = true;

  __structuredAttrs = true;
  strictDeps = true;

  passthru = rec {
    # The result is a set of two attributes
    moduleStructuredConfig =
      (lib.evalModules {
        modules = [
          (path + "/nixos/modules/system/boot/kernel_config.nix")
          {
            settings =
              kconfig
              // (lib.optionalAttrs default kconfigs.default);
            _file = "structuredExtraConfig";
          }
        ];
      })
        .config;

    structuredConfig = moduleStructuredConfig.settings;
  };
}
