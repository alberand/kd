{
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
    xfsprogs = prev.xfsprogs.overrideAttrs (old: {
      inherit version;
      src = if cfg.src != null then cfg.src else old.src;

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
        ];

      # Here we need to add a few more files to the for-loop as in newer version
      # of xfsprogs there's more references to @sbindir@. No doing so will cause
      # cycle error
      # for file in scrub/{xfs_scrub_all.cron.in,xfs_scrub@.service.in,xfs_scrub_all.service.in}; do
      preConfigure = ''
        for file in scrub/{xfs_scrub_all.cron.in,xfs_scrub@.service.in,xfs_scrub_all.service.in,xfs_scrub_all.in,xfs_scrub_media@.service.in}; do
          substituteInPlace "$file" \
            --replace '@sbindir@' '/run/current-system/sw/bin'
        done
        patchShebangs ./install-sh
      '';

      postConfigure = ''
        cp include/install-sh install-sh
        patchShebangs ./install-sh
      '';
    });
  };
in {
  options.programs.xfsprogs = {
    enable = mkEnableOption {
      name = "xfsprogs";
      default = false;
      example = true;
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = null;
    };
  };

  config = mkIf cfg.enable {
    nixpkgs.overlays = [
      (xfsprogs-overlay {
        inherit (cfg) src;
        version = "git";
      })
    ];

    environment.systemPackages = with pkgs; [
      xfsprogs
    ];
  };
}
