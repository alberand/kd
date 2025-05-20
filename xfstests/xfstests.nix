{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.programs.xfstests;
  xfstests-overlay-remote = final: prev: rec {
    xfstests-configs = import ./configs.nix {inherit pkgs;};

    xfstests-hooks = pkgs.stdenv.mkDerivation {
      name = "xfstests-hooks";
      src = cfg.hooks;
      phases = ["unpackPhase" "installPhase"];
      installPhase = ''
        runHook preInstall

        mkdir -p $out/lib/xfstests/hooks
        cp --no-preserve=mode -r $src/* $out/lib/xfstests/hooks

        runHook postInstall
      '';
    };
    github-upload =
      pkgs.writeShellScriptBin "github-upload" (builtins.readFile
        ./github-upload.sh);
    xfstests = pkgs.symlinkJoin {
      name = "xfstests";
      paths =
        [
          (prev.xfstests.overrideAttrs (old: {
            stdenv = prev.ccacheStdenv;
            inherit (cfg) src;
            version = "git";
            patchPhase =
              builtins.readFile ./patchPhase.sh
              + old.patchPhase;
            patches =
              (old.patches or [])
              ++ [
                ./0001-common-link-.out-file-to-the-output-directory.patch
                ./0002-common-fix-linked-binaries-such-as-ls-and-true.patch
              ];
            nativeBuildInputs =
              old.nativeBuildInputs
              ++ [pkgs.pkg-config pkgs.gdbm pkgs.liburing]
              ++ lib.optionals (cfg.kernelHeaders != null) [cfg.kernelHeaders];

            wrapperScript = with pkgs;
              writeScript "xfstests-check" (''
                  #!${pkgs.runtimeShell}
                  set -e

                  dir=$(mktemp --tmpdir -d xfstests.XXXXXX)
                  trap "rm -rf $dir" EXIT

                  chmod a+rx "$dir"
                  cd "$dir"
                  for f in $(cd @out@/lib/xfstests; echo *); do
                    ln -s @out@/lib/xfstests/$f $f
                  done
                ''
                + (optionalString (cfg.hooks != null) ''
                  ln -s ${pkgs.xfstests-hooks}/lib/xfstests/hooks hooks
                '')
                + ''
                  export PATH=${lib.makeBinPath [
                    acl
                    attr
                    bc
                    e2fsprogs
                    gawk
                    keyutils
                    libcap
                    lvm2
                    perl
                    procps
                    killall
                    quota
                    util-linux
                    which
                    xfsprogs
                    duperemove
                    acct
                    xfsdump
                    indent
                    man
                    fio
                    dbench
                    thin-provisioning-tools
                    file
                    openssl
                  ]}:$PATH
                  exec ./check "$@"
                '');
          }))
        ]
        ++ optionals (cfg.hooks != null) [
          xfstests-hooks
        ];
    };
  };
in {
  options.programs.xfstests = {
    enable = mkEnableOption {
      name = "xfstests";
      default = true;
      example = true;
    };

    arguments = mkOption {
      description = "command line arguments for xfstests";
      # Has to be empty by default to not run anything in VM
      default = "";
      example = "-g auto";
      type = types.str;
    };

    test-dev = mkOption {
      description = "Path to disk used as TEST_DEV";
      default = "";
      example = "/dev/sda";
      type = types.str;
    };

    scratch-dev = mkOption {
      description = "Path to disk used as SCRATCH_DEV";
      default = "";
      example = "/dev/sdb";
      type = types.str;
    };

    extraEnv = mkOption {
      description = "Extra environment for xfstests";
      default = "";
      example = ''
        export LOGWRITES_DEV=/dev/sdc
        export SCRATCH_LOGDEV=/dev/sdd
      '';
      type = types.str;
    };

    testconfig = mkOption {
      description = "xfstests configuration file";
      default = "${pkgs.xfstests-configs.xfstests-all}";
      example = "./local.config.example";
      type = types.path;
    };

    autoshutdown = mkOption {
      description = "autoshutdown machine after test is complete";
      default = false;
      example = false;
      type = types.bool;
    };

    pre-test-hook = mkOption {
      description = "bash script run before test execution";
      default = "";
      example = "trace-cmd start -e xfs";
      type = types.str;
    };

    post-test-hook = mkOption {
      description = "bash script run after test execution";
      default = "";
      example = "trace-cmd stop; trace-cmd show > /root/trace.log";
      type = types.str;
    };

    hooks = mkOption {
      description = "Path to hooks folder. 20210722064725.3077558-1-david@fromorbit.com";
      default = null;
      example = "./xfstests-hooks";
      type = types.nullOr types.path;
    };

    mkfs_cmd = mkOption {
      description = "mkfs command to recreate the disks before tests";
      default = "${pkgs.xfsprogs}/bin/mkfs.xfs";
      example = "${pkgs.xfsprogs}/bin/mkfs.xfs";
      type = types.str;
    };

    mkfs_opts = mkOption {
      description = "Options for mkfs_cmd";
      default = "";
      example = "-f";
      type = types.str;
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = pkgs.fetchgit {
        url = "git://git.kernel.org/pub/scm/fs/xfs/xfstests-dev.git";
        rev = "v2024.12.22";
        sha256 = "sha256-xZkCZVvlcnqsUnGGxSFqOHoC73M9ijM5sQnnRqamOk8=";
      };
    };

    repository = mkOption {
      description = "GitHub repository to upload results to";
      default = "";
      example = "https://github.com/alberand/xfstests-results";
      type = types.str;
    };

    upload-results = mkOption {
      description = "Upload results to GitHub repository";
      default = false;
      example = true;
      type = types.bool;
    };

    kernelHeaders = mkOption {
      type = types.nullOr types.package;
      description = "Linux kernel headers to compile xfstests against";
      default = null;
    };
  };

  config = mkIf cfg.enable {
    warnings = (
      lib.optionals (cfg.upload-results && (cfg.repository == ""))
      "To upload results set programs.xfstests.repository"
    );

    nixpkgs.overlays = [
      xfstests-overlay-remote
    ];

    environment.systemPackages = with pkgs; [
      xfstests
      xfsprogs
    ];

    # Setup envirionment
    environment.variables = {
      HOST_OPTIONS =
        pkgs.writeText "xfstests.config"
        (builtins.readFile cfg.testconfig);
    };

    users = {
      users = {
        daemon = {
          isNormalUser = true;
          description = "Test user";
        };

        fsgqa = {
          isNormalUser = true;
          description = "Test user";
          uid = 2000;
          group = "fsgqa";
        };

        fsgqa2 = {
          isNormalUser = true;
          description = "Test user";
          uid = 2001;
          group = "fsgqa2";
        };

        "123456-fsgqa" = {
          isNormalUser = true;
          description = "Test user";
          uid = 2002;
          group = "123456-fsgqa";
        };

        bin = {
          isNormalUser = true;
          description = "Test user";
          uid = 2003;
          group = "bin";
        };
      };

      groups = {
        fsgqa = {
          gid = 2000;
          members = ["fsgqa"];
        };

        fsgqa2 = {
          gid = 2001;
          members = ["fsgqa2"];
        };

        "123456-fsgqa" = {
          gid = 2002;
          members = ["123456-fsgqa"];
        };

        bin = {
          gid = 2003;
          members = ["bin"];
        };

        sys = {
          gid = 2004;
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d /mnt 1777 root root"
      "d /mnt/test 1777 root root"
      "d /mnt/scratch 1777 root root"
    ];

    # TODO Do we need this at all? Shouldn't this be done by service
    fileSystems =
      lib.mkIf (cfg.test-dev != "") {
        "/mnt/test" = {
          device = cfg.test-dev;
          fsType = "xfs";
          options = ["nofail"];
        };
      }
      // lib.mkIf (cfg.scratch-dev != "") {
        "/mnt/scratch" = {
          device = cfg.scratch-dev;
          fsType = "xfs";
          options = ["nofail"];
        };
      };

    systemd.services.xfstests = {
      enable = true;
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "tty";
        StandardError = "tty";
        # argh... Nix ignore SIGPIPE somewhere and it causes all child processes
        # to ignore SIGPIPE. Don't remove it or otherwise many tests will fail
        # due too Broken pipe. Test with yes | head should not return Brokne
        # pipe.
        IgnoreSIGPIPE = "no";
        User = "root";
        Group = "root";
        WorkingDirectory = "/root";
      };
      after = ["network.target" "network-online.target" "local-fs.target"];
      wants = ["network.target" "network-online.target" "local-fs.target"];
      wantedBy = ["multi-user.target"];
      postStop =
        ''
          ${cfg.post-test-hook}
          # Beep beep... Human... back to work
          echo -ne '\007'
        ''
        + optionalString cfg.autoshutdown ''
          # Auto poweroff
          ${pkgs.systemd}/bin/systemctl poweroff;
        '';
      script =
        ''
          ${cfg.pre-test-hook}

          function get_config {
            ${pkgs.tomlq}/bin/tq --file /root/share/kd.toml $@
          }

          if [ ! -f "/root/share/kd.toml" ] && [ "${cfg.arguments}" == "" ]; then
            echo "/root/share/kd.toml: file doesn't exist"
            exit 0
          fi

          if [ "$(get_config 'xfstests.args')" == "" ] && [ "${cfg.arguments}" == "" ]; then
            echo "No tests to run according to /root/share/kd.toml"
            exit 0
          fi

          arguments=""
          if [ "$(get_config 'xfstests.args')" != "" ]; then
            arguments="$(get_config 'xfstests.args')"
          else
            arguments="${cfg.arguments}"
          fi;

          mkfs_opts=""
          if [ "$(get_config 'xfstests.mkfs_opts')" != "" ]; then
            mkfs_opts="$(get_config 'xfstests.mkfs_opts')"
          else
            mkfs_opts="${cfg.mkfs_opts}"
          fi;

          test_dev=""
          if [ "$(get_config 'xfstests.test_dev')" != "" ]; then
            test_dev="$(get_config 'xfstests.test_dev')"
          else
            test_dev="${cfg.test-dev}"
          fi;

          scratch_dev=""
          if [ "$(get_config 'xfstests.scratch_dev')" != "" ]; then
            scratch_dev="$(get_config 'xfstests.scratch_dev')"
          else
            scratch_dev="${cfg.scratch-dev}"
          fi;

          if ${pkgs.util-linux}/bin/mountpoint /mnt/test; then
            ${pkgs.util-linux}/bin/umount $test_dev
          fi
          if ${pkgs.util-linux}/bin/mountpoint /mnt/scratch; then
            ${pkgs.util-linux}/bin/umount $scratch_dev
          fi
          ${cfg.mkfs_cmd} -f $mkfs_opts -L test $test_dev
          ${cfg.mkfs_cmd} -f $mkfs_opts -L scratch $scratch_dev

          export TEST_DEV="$test_dev"
          export SCRATCH_DEV="$scratch_dev"
          ${cfg.extraEnv}
          ${pkgs.bash}/bin/bash -lc \
            "${pkgs.xfstests}/bin/xfstests-check $arguments"

        ''
        + (optionalString (cfg.upload-results) ''
          ${pkgs.github-upload}/bin/github-upload \
            ${cfg.repository} \
            ${config.networking.hostName} \
            /root/results
        '');
    };
  };
}
