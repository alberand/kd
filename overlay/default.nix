{
  pkgs,
  lib,
}: final: prev: rec {
  kconfigs = import ../kconfigs/default.nix {inherit (pkgs) lib;};

  xfsprogs = let
    sources = prev.lib.importJSON ../sources/xfsprogs.json;
  in (prev.xfsprogs.overrideAttrs (
    old:
      {
        src = prev.fetchgit sources;
        version = "git-${sources.rev}";

        # Drop Python as this is necessary for protofiles and xfs_scrub only but
        # adds ~100MB to the image
        buildInputs =
          prev.lib.lists.remove (prev.python3.withPackages (ps: [
            ps.dbus-python
          ]))
          old.buildInputs;
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

        patches = [];

        # Even with documentation.man.enable = false; install a manual pages for
        # xfsprogs package. This is necessary for some xfstests (xfs/505,
        # xfs/514, xfs/515, xfs/293)
        outputs =
          old.outputs or [
            "out"
            "man"
          ];
        postInstall =
          (old.postInstall or "")
          + ''
            # Ensure man pages are kept
          '';

        preConfigure =
          prev.xfsprogs.preConfigure
          + ''
            patchShebangs libfrog/gettext.py.in mkfs/xfs_protofile.py.in
          '';

        postConfigure = ''
          cp include/install-sh install-sh
          patchShebangs ./install-sh
        '';
      }
      // prev.lib.optionalAttrs false {
        stdenv = prev.ccacheStdenv;
      }
  ));

  xfstests-configs = prev.stdenv.mkDerivation {
    name = "xfstests-configs";
    version = "v1";
    src = ../xfstests;
    installPhase = ''
      mkdir -p $out
      cp $src/*.conf $out
    '';
    passthru = {
      xfstests-all = ../xfstests/xfstests-all.conf;
      xfstests-xfs-1k = ../xfstests/xfstests-xfs-1k.conf;
      xfstests-xfs-4k = ../xfstests/xfstests-xfs-4k.conf;
      xfstests-ext4-1k = ../xfstests/xfstests-ext4-1k.conf;
      xfstests-ext4-4k = ../xfstests/xfstests-ext4-4k.conf;
    };
  };

  xfstests-hooks = prev.stdenv.mkDerivation {
    name = "xfstests-hooks";
    src = prev.fetchFromGitHub {
      owner = "alberand";
      repo = "xfstests-hooks";
      rev = "efce2671f15498d30ab7a1bb2ff76f67e454970b";
      hash = "sha256-YQG4EoIdIeXiZENOfq6sTqN2e5SKRz9hHwslEgoC61Y=";
    };

    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/xfstests/hooks
      cp --no-preserve=mode -r $src/* $out/lib/xfstests/hooks

      runHook postInstall
    '';
  };

  xfstests-upload = prev.writeShellScriptBin "xfstests-upload" (
    builtins.readFile ../xfstests/github-upload.sh
  );

  xfstests = prev.xfstests.overrideAttrs (
    old: let
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

          sed -e 's|/usr/share/xfsprogs|${xfsprogs}/share|' -i tests/xfs/569

          patchShebangs .
        '';
        patches = [
          ../xfstests/0001-common-link-.out-file-to-the-output-directory.patch
          ../xfstests/0002-common-fix-linked-binaries-such-as-ls-and-true.patch
          ../xfstests/0003-generic-746-follow-symlinks-when-populating-mount.patch
          ../xfstests/0004-fstests-generic-test-hook-infrastructure.patch
          ../xfstests/0005-hooks-make-hooks-directory-changable-with-HOOK_DIR.patch
        ];

        nativeBuildInputs =
          old.nativeBuildInputs
          ++ [
            prev.pkg-config
            prev.gdbm
            prev.liburing
          ];

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
          export MANPATH="${final.xfsprogs.man}/share/man"
          export PATH=${
            prev.lib.makeBinPath [
              final.xfsprogs
              final.acl
              final.attr
              final.bc
              final.e2fsprogs
              final.gawk
              final.keyutils
              final.libcap
              final.lvm2
              final.perl
              final.procps
              final.killall
              final.quota
              final.util-linux
              final.which
              final.acct
              final.xfsdump
              final.indent
              final.man
              final.thin-provisioning-tools
              final.file
              final.openssl
              final.checkbashisms # xfs mainteiner test
              final.findutils
            ]
          }:$PATH
          exec ./check "$@"
        '';
      }
      // prev.lib.optionalAttrs false {
        stdenv = prev.ccacheStdenv;
      }
  );

  kd = (
    pkgs.callPackage (import ../kd/derivation.nix) {
      inherit (pkgs.lib) makeBinPath fileset;
    }
  );

  drgn = pkgs.callPackage ../pkgs/drgn/derivation.nix {};

  # xfsdump don't yet use flexible arrays. NixOS uses FORTIFY_SOURCE by default
  # starting 26.05. Fixing xfsdump isn't that straightforward, so disable
  # fortify.
  # https://maskray.me/blog/2022-11-06-fortify-source
  # https://sourceforge.net/p/cdesktopenv/tickets/193/
  # https://sourceware.org/glibc/manual/latest/html_node/Source-Fortification.html
  xfsdump = prev.xfsdump.overrideAttrs (
    final: prev: {
      hardeningDisable = ["fortify"];
    }
  );
}
