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
      type = types.package;
      description = "Linux kernel headers to compile xfsprogs against";
      default = let
        src = pkgs.fetchgit (pkgs.lib.importJSON ../sources/kernel.json);
      in
        pkgs.makeLinuxHeaders {
          version = src.rev;
          inherit src;
        };
    };

    enablePython = mkOption {
      type = types.bool;
      default = false;
      description = "Add python (image gains ~100MB)";
    };
  };

  config = mkIf cfg.enable (
    let
      xfsprogs = (
        pkgs.xfsprogs.overrideAttrs (
          _final: prev: (
            {
              inherit (cfg) src;
              version = "git-${cfg.src.rev}";

              buildInputs =
                prev.buildInputs
                ++ (lib.optionals (cfg.enablePython) [
                  (python3.withPackages (ps: [ps.dbus-python]))
                ]);

              nativeBuildInputs = [cfg.kernelHeaders] ++ prev.nativeBuildInputs;
              dontStrip = config.dev.dontStrip;
            }
            // lib.optionalAttrs false {
              stdenv = pkgs.ccacheStdenv;
            }
          )
        )
      );
    in {
      environment.variables = {
        XFSPROGS_SRC = "${xfsprogs.src}";
      };

      environment.systemPackages = [
        xfsprogs
      ];
    }
  );
}
