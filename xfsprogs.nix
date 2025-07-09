{enableCcache ? false}: {
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.programs.xfsprogs;
  xfsprogs-overlay = {
    version,
    src ? null,
  }: final: prev: {
    xfsprogs = prev.xfsprogs.overrideAttrs (old:
      {
        inherit version;
        src =
          if cfg.src != null
          then cfg.src
          else old.src;

        # We need to add autoconfHook because if you look into nixpkgs#xfsprogs
        # the source code fetched is not a git tree - it's tarball. The tarball is
        # actually created with 'make dist' command. This tarball already has some
        # additional stuff produced by autoconf. Here we want to take raw git tree
        # so we need to run 'make dist', but this is not the best way (why?), just
        # add autoreconfHook which will do autoconf automatically.
        nativeBuildInputs =
          prev.xfsprogs.nativeBuildInputs
          ++ [
            pkgs.autoreconfHook
            pkgs.attr
          ]
          ++ lib.optionals (cfg.kernelHeaders != null) [
            cfg.kernelHeaders
          ];

        postConfigure = ''
          cp include/install-sh install-sh
          patchShebangs ./install-sh
        '';

        dontStrip = config.dev.dontStrip;

        # Let's check for a version
        nativeInstallCheckInputs = [
          versionCheckHook
        ];
        versionCheckProgram = "${placeholder "out"}/bin/mkfs.xfs";
        versionCheckProgramArg = "-V";
        doInstallCheck = true;
      }
      // lib.optionalAttrs enableCcache {
        stdenv = prev.ccacheStdenv;
      });
  };
in {
  options.programs.xfsprogs = {
    enable = mkEnableOption {
      name = "xfsprogs";
      default = true;
      example = true;
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = pkgs.fetchgit {
        url = "git://git.kernel.org/pub/scm/fs/xfs/xfsprogs-dev.git";
        rev = "v6.14.0";
        sha256 = "sha256-jngn0xvTyWtDsKZWTMerw4sqsval0KcmTnkfkXuoGbM=";
      };
    };

    kernelHeaders = mkOption {
      type = types.nullOr types.package;
      description = "Linux kernel headers to compile xfsprogs against";
      default = null;
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (xfsprogs-overlay {
        src =
          if (cfg.src != null)
          then cfg.src
          else prev.src;
        version = "git";
      })
    ];

    environment.systemPackages = with pkgs; [
      xfsprogs
    ];
  };
}
