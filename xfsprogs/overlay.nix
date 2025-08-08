{enableCcache ? false}: final: prev: let
  sources = prev.lib.importJSON ../sources/xfsprogs.json;
in {
  xfsprogs = prev.xfsprogs.overrideAttrs (old:
    {
      src = prev.fetchgit sources;
      version = "git-${sources.rev}";

      # We need to add autoconfHook because if you look into nixpkgs#xfsprogs
      # the source code fetched is not a git tree - it's tarball. The tarball is
      # actually created with 'make dist' command. This tarball already has some
      # additional stuff produced by autoconf. Here we want to take raw git tree
      # so we need to run 'make dist', but this is not the best way (why?), just
      # add autoreconfHook which will do autoconf automatically.
      nativeBuildInputs =
        prev.xfsprogs.nativeBuildInputs
        ++ [
          prev.autoreconfHook
          prev.attr
        ];

      preConfigure = prev.xfsprogs.preConfigure + ''
        patchShebangs libfrog/gettext.py.in mkfs/xfs_protofile.py.in
      '';

      postConfigure = ''
        cp include/install-sh install-sh
        patchShebangs ./install-sh
      '';
    }
    // prev.lib.optionalAttrs enableCcache {
      stdenv = prev.ccacheStdenv;
    });
}
