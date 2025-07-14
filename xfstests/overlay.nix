{enableCcache ? false}: final: prev: rec {
  xfstests-configs = prev.stdenv.mkDerivation {
    name = "xfstests-configs";
    version = "v1";
    src = ./.;
    installPhase = ''
      mkdir -p $out
      cp $src/*.conf $out
    '';
    passthru = {
      xfstests-all = ./xfstests-all.conf;
      xfstests-xfs-1k = ./xfstests-xfs-1k.conf;
      xfstests-xfs-4k = ./xfstests-xfs-4k.conf;
      xfstests-ext4-1k = ./xfstests-ext4-1k.conf;
      xfstests-ext4-4k = ./xfstests-ext4-4k.conf;
    };
  };

  xfstests-hooks = prev.stdenv.mkDerivation {
    name = "xfstests-hooks";
    src = prev.fetchFromGitHub {
      owner = "alberand";
      repo = "xfstests-hooks";
      rev = "82f344c67d981c6f9fe4521536ecfcdc00b84b0d";
      hash = "sha256-sIpM73g/KMsflQQ4Hkkc8YLzgjTwJfsp22oATNj3DSs=";
    };

    phases = ["unpackPhase" "installPhase"];
    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/xfstests/hooks
      cp --no-preserve=mode -r $src/* $out/lib/xfstests/hooks

      runHook postInstall
    '';
  };

  xfstests-upload =
    prev.writeShellScriptBin "xfstests-upload" (builtins.readFile
      ./github-upload.sh);

  xfstests = prev.xfstests.overrideAttrs (old: let
    sources = prev.lib.importJSON ../sources/xfstests.json;
  in
    {
      src = prev.fetchgit sources;
      version = "git-${sources.rev}";
      patchPhase = with prev; ''
        # Apply patches if any
        local -a patchesArray
        patchesArray=( ''${patches[@]:-} )
        for p in "''${patchesArray[@]}"; do
          echo "applying patch $p"
          patch -p1 < $p
        done

        # As install-sh is taken from the /nix/store by libtoolize, it's read-only. The
        # Makefile can not overwrite it latter. Fix this by telling cp to force
        # overwrite.
        substituteInPlace Makefile \
          --replace "cp include/install-sh ." "cp -f include/install-sh ."

        # Patch the destination directory
        sed -i include/builddefs.in -e "s|^PKG_LIB_DIR\s*=.*|PKG_LIB_DIR=$out/lib/xfstests|"

        # Don't canonicalize path to mkfs (in util-linux) - otherwise e.g. mkfs.ext4 isn't found
        sed -i common/config -e 's|^export MKFS_PROG=.*|export MKFS_PROG=mkfs|'

        # Move the Linux-specific test output files to the correct place, or else it will
        # try to move them at runtime. Also nuke all the irix crap.
        for f in tests/*/*.out.linux; do
          mv $f $(echo $f | sed -e 's/\.linux$//')
        done
        rm -f tests/*/*.out.irix

        # Fix up lots of impure paths
        for f in common/* tools/* tests/*/*; do
          sed -i $f -e 's|/bin/bash|${bash}/bin/bash|'
          sed -i $f -e 's|/bin/true|${coreutils}/bin/true|'
          sed -i $f -e 's|/usr/sbin/filefrag|${e2fsprogs}/bin/filefrag|'
          # `hostname -s` seems problematic on NixOS
          sed -i $f -e 's|hostname -s|${hostname}/bin/hostname|'
          # NixOS won't ever have Yellow Pages enabled
          sed -i $f -e 's|$(_yp_active)|1|'
        done

        for f in src/*.c src/*.sh; do
          sed -e 's|/bin/rm|${coreutils}/bin/rm|' -i $f
          sed -e 's|/usr/bin/time|${time}/bin/time|' -i $f
        done

        patchShebangs .
      '';
      patches = [
        ./0001-common-link-.out-file-to-the-output-directory.patch
        ./0002-common-fix-linked-binaries-such-as-ls-and-true.patch
      ];

      nativeBuildInputs =
        old.nativeBuildInputs
        ++ [prev.pkg-config prev.gdbm prev.liburing];

      postInstall =
        old.postInstall
        + ''
          ln -s ${xfstests-hooks}/lib/xfstests/hooks $out/lib/xfstests/hooks
        '';

      wrapperScript = prev.writeScript "xfstests-check" ''
        #!${prev.runtimeShell}
        set -e

        dir=$(mktemp --tmpdir -d xfstests.XXXXXX)
        trap "rm -rf $dir" EXIT

        chmod a+rx "$dir"
        cd "$dir"
        for f in $(cd @out@/lib/xfstests; echo *); do
          ln -s @out@/lib/xfstests/$f $f
        done
        export PATH=${prev.lib.makeBinPath [
          final.xfsprogs
          prev.acl
          prev.attr
          prev.bc
          prev.e2fsprogs
          prev.gawk
          prev.keyutils
          prev.libcap
          prev.lvm2
          prev.perl
          prev.procps
          prev.killall
          prev.quota
          prev.util-linux
          prev.which
          prev.duperemove
          prev.acct
          prev.xfsdump
          prev.indent
          prev.man
          prev.fio
          prev.thin-provisioning-tools
          prev.file
          prev.openssl
        ]}:$PATH
        exec ./check "$@"
      '';
    }
    // prev.lib.optionalAttrs enableCcache {
      stdenv = prev.ccacheStdenv;
    });
}
