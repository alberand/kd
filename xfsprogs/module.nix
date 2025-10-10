{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.services.xfsprogs;
in {
  options.services.xfsprogs = {
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
    environment.systemPackages = with pkgs; [
      (xfsprogs.overrideAttrs (_final: prev: ({
          inherit (cfg) src;
          version = "git-${cfg.src.rev}";

          nativeBuildInputs =
            pkgs.lib.optionals (cfg.kernelHeaders != null) [
              cfg.kernelHeaders
            ]
            ++ prev.nativeBuildInputs;

          dontStrip = config.dev.dontStrip;
        }
        // lib.optionalAttrs false {
          stdenv = pkgs.ccacheStdenv;
        })))
    ];
  };
}
