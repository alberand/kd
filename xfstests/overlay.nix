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
      patchPhase = old.patchPhase +
        builtins.readFile ./patchPhase.sh;
      patches =
        (old.patches or [])
        ++ [
          ./0001-common-link-.out-file-to-the-output-directory.patch
          ./0002-common-fix-linked-binaries-such-as-ls-and-true.patch
        ];
      nativeBuildInputs =
        old.nativeBuildInputs
        ++ [prev.pkg-config prev.gdbm prev.liburing];

      postInstall = old.postInstall + ''
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
