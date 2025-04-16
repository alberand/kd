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
  options.kernel = {
    version = mkOption {
      type = types.str;
      default = "v6.14";
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = pkgs.fetchFromGitHub {
        owner = "torvalds";
        repo = "linux";
        rev = "v6.14";
        hash = "sha256-5Fkx6y9eEKuQVbDkYh3lxFQrXCK4QJkAZcIabj0q/YQ=";
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
  };

  config = let
    buildKernel = pkgs.callPackage ./kernel-build.nix {};
    buildKernelConfig = pkgs.callPackage ./kernel-config.nix {inherit nixpkgs;};
  in {
    boot.kernelPackages = pkgs.linuxPackagesFor (
      buildKernel {
        inherit (cfg) version src;
        kconfig = buildKernelConfig {
          inherit (cfg) src version kconfig iso debug;
        };
      }
    );
  };
}
