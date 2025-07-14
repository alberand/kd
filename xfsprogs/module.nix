{enableCcache ? false}: {
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.programs.xfsprogs;
in {
  options.programs.xfsprogs = {
    enable = mkEnableOption {
      name = "xfsprogs";
      default = true;
      example = true;
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = pkgs.fetchgit (pkgs.lib.importJSON ../sources/xfsprogs.json);
    };

    kernelHeaders = mkOption {
      type = types.nullOr types.package;
      description = "Linux kernel headers to compile xfsprogs against";
      default = null;
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (_final: prev: {
        xfsprogs =
          prev.xfsprogs.overrideAttrs {
            inherit (cfg) src;
            version = "git-${cfg.src.rev}";

            nativeInstallCheckInputs =
              prev.xfsprogs.nativeInstallCheckInputs
              ++ lib.optionals (cfg.kernelHeaders != null) [
                cfg.kernelHeaders
              ];

            dontStrip = config.dev.dontStrip;
          }
          // lib.optionalAttrs enableCcache {
            stdenv = prev.ccacheStdenv;
          };
      })
    ];

    environment.systemPackages = with pkgs; [
      xfsprogs
    ];
  };
}
