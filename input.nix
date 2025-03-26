{
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
      default = "v6.13";
    };

    modDirVersion = mkOption {
      type = types.str;
      default = "6.13.0";
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = pkgs.fetchFromGitHub {
        owner = "torvalds";
        repo = "linux";
        rev = "v6.13";
        hash = "sha256-FD22KmTFrIhED5X3rcjPTot1UOq1ir1zouEpRWZkRC0=";
      };
    };

    kconfig = mkOption {
      type = types.nullOr types.attrs;
      default = {};
    };
  };

  config = let
    buildKernel = pkgs.callPackage ./kernel-build.nix {};
  in {
    boot.kernelPackages = pkgs.linuxPackagesFor (
      buildKernel {
        inherit (cfg) version modDirVersion src kconfig;
      }
    );
  };
}
