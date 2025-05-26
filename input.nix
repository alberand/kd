# This is guest module. In other words, it's options which could be set in the
# VM or ISO. These options are just convenient wrappers. However, they also
# set default values to these options.
{nixpkgs}: {
  pkgs,
  config,
  ...
}:
with pkgs.lib; let
  cfg = config.kernel;
in {
  options = {
    dev = {
      dontStrip = mkOption {
        type = types.bool;
        default = false;
      };
    };

    kernel = {
      version = mkOption {
        type = types.str;
        default = "6.14.5";
      };

      src = mkOption {
        type = types.nullOr types.package;
        default = pkgs.fetchgit {
          url = "git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git";
          rev = "v6.14.5";
          hash = "sha256-9FVjWxVurrsPqT3hSRHnga3T6Aj3MMCqtpC2+rPfm6U=";
        };
      };

      kconfig = mkOption {
        type = types.attrs;
        default = {};
      };

      # TODO this has to be config level options
      iso = mkOption {
        type = types.bool;
        default = false;
      };

      debug = mkOption {
        type = types.bool;
        default = false;
      };

      prebuild = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
    };
  };

  config = let
    buildKernel = pkgs.callPackage ./kernel-build.nix {};
    buildKernelConfig = pkgs.callPackage ./kernel-config.nix {inherit nixpkgs;};
    kernelPackages = pkgs.linuxPackagesFor (
      buildKernel {
        inherit (cfg) version src;
        kconfig = buildKernelConfig {
          inherit (cfg) src version kconfig iso debug;
        };
      }
    );
  in {
    # If no prebuild, just build a normal kernel
    boot.kernelPackages =
      if cfg.prebuild == null
      then kernelPackages
      else
        # First thing to do is to remove default kernel package which is set
        # in input.nix
        #
        # Second thing is to replace this kernel package with this ad-hoc
        # derivation which just takes artifacts of the prebuild kernel and
        # copies them to the /nix/store.
        #
        # This derivation has some random stuff attached to it at the end with
        # // {}. This is due to the fact that kernel package is not just a
        # derivation and has much more function used throughout the system.
        #
        # As this is dummy non-functional derivation a lot of stuff which
        # checks for kernel configurations options, checks for kernel modules,
        # any other kernel related state, won't work at all.
        #
        # The last step is to pass buildRoot directory to the derivation. As
        # this is not declarative building #prebuild requires --impure mode.
        (builtins.removeAttrs kernelPackages ["kernel"])
        .extend (_final: prev: {
          kernel = let
            kf = {buildRoot}: {stdenv, ...}:
              (stdenv.mkDerivation {
                name = "prebuild-kernel";
                version = "git";
                modDirVersion = "git";
                phases = ["installPhase"];
                src = buildRoot;
                installPhase = ''
                  echo "Install phase"
                  mkdir -p $out
                  cp -r $src/* $out/
                '';
                outputs = ["out"];
              })
              // rec {
                config = "";
                baseVersion = pkgs.lib.head (pkgs.lib.splitString "-rc" prev.kernel.version);
                kernelOlder = pkgs.lib.versionOlder baseVersion;
                kernelAtLeast = pkgs.lib.versionAtLeast baseVersion;
              };
          in
            pkgs.callPackage (kf {
              buildRoot = cfg.prebuild;
            }) {};
        });
  };
}
