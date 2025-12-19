{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.services.xfstests;
in {
  options.services.xfstests = {
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

    dev = {
      test = {
        main = mkOption {
          description = "Path to disk used as TEST_DEV";
          default = "";
          example = "/dev/sda";
          type = types.str;
        };

        rtdev = mkOption {
          description = "Path to disk used as TEST_RTDEV";
          default = "";
          example = "/dev/sdc";
          type = types.str;
        };

        logdev = mkOption {
          description = "Path to disk used as TEST_LOGDEV";
          default = "";
          example = "/dev/sdd";
          type = types.str;
        };
      };

      scratch = {
        main = mkOption {
          description = "Path to disk used as SCRATCH_DEV";
          default = "";
          example = "/dev/sdb";
          type = types.str;
        };

        rtdev = mkOption {
          description = "Path to disk used as SCRATCH_RTDEV";
          default = "";
          example = "/dev/sdc";
          type = types.str;
        };

        logdev = mkOption {
          description = "Path to disk used as SCRATCH_LOGDEV";
          default = "";
          example = "/dev/sdd";
          type = types.str;
        };
      };
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

    hooks = mkOption {
      description = "Path to hooks folder. 20210722064725.3077558-1-david@fromorbit.com";
      default = null;
      example = "./xfstests-hooks";
      type = types.nullOr types.path;
    };

    filesystem = mkOption {
      description = "Filesystem to format disks to before xfstests";
      default = "xfs";
      example = "ext4";
      type = types.str;
    };

    src = mkOption {
      type = types.nullOr types.package;
      default = pkgs.fetchgit (pkgs.lib.importJSON ../sources/xfstests.json);
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
      type = types.package;
      description = "Linux kernel headers to compile xfstests against";
      default = let
        src = pkgs.fetchgit (pkgs.lib.importJSON ../sources/kernel.json);
      in
        pkgs.makeLinuxHeaders {
          version = src.rev;
          inherit src;
        };
    };
  };

  config = let
    xfspcfg = config.services.xfsprogs;
    xfsprogs = pkgs.xfsprogs.overrideAttrs (_final: prev: ({
        inherit (xfspcfg) src;
        version = "git-${xfspcfg.src.rev}";

        nativeBuildInputs = [xfspcfg.kernelHeaders] ++ prev.nativeBuildInputs;

        dontStrip = config.dev.dontStrip;
      }
      // lib.optionalAttrs false {
        stdenv = pkgs.ccacheStdenv;
      }));
    xfstests = pkgs.xfstests.overrideAttrs (_final: prev: ({
        inherit (cfg) src;
        version = "git-${cfg.src.rev}";

        nativeBuildInputs = prev.nativeBuildInputs ++ [cfg.kernelHeaders];

        dontStrip = config.dev.dontStrip;

        wrapperScript = pkgs.writeScript "xfstests-check" ''
          #!${pkgs.runtimeShell}
          set -e

          dir=$(mktemp --tmpdir -d xfstests.XXXXXX)
          trap "rm -rf $dir" EXIT

          chmod a+rx "$dir"
          cd "$dir"
          for f in $(cd @out@/lib/xfstests; echo *); do
            ln -s @out@/lib/xfstests/$f $f
          done
          export PATH=${pkgs.lib.makeBinPath [
            xfsprogs
            pkgs.acl
            pkgs.attr
            pkgs.bc
            pkgs.e2fsprogs
            pkgs.gawk
            pkgs.keyutils
            pkgs.libcap
            pkgs.lvm2
            pkgs.perl
            pkgs.procps
            pkgs.killall
            pkgs.quota
            pkgs.util-linux
            pkgs.which
            pkgs.duperemove # pulls glib
            pkgs.acct
            pkgs.xfsdump
            pkgs.indent
            pkgs.man
            pkgs.fio # brings Python 3
            pkgs.thin-provisioning-tools
            pkgs.file
            pkgs.openssl
            pkgs.checkbashisms # xfs mainteiner test
            pkgs.findutils
          ]}:$PATH
          exec ./check "$@"
        '';
      }
      // pkgs.lib.optionalAttrs false {
        stdenv = pkgs.ccacheStdenv;
      }));
  in
    mkIf cfg.enable
    {
      warnings = (
        lib.optionals (cfg.upload-results && (cfg.repository == ""))
        "To upload results set services.xfstests.repository"
      );

      # Setup envirionment
      environment.variables = {
        XFSTESTS_SRC = "${xfstests.src}";
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
        lib.mkIf (cfg.dev.test.main != "") {
          "/mnt/test" = {
            device = cfg.dev.test.main;
            fsType = "xfs";
            options = ["nofail"];
          };
        }
        // lib.mkIf (cfg.dev.test.rtdev != "") {
          "/mnt/test_rtdev" = {
            device = cfg.dev.test.rtdev;
            fsType = "xfs";
            options = ["nofail"];
          };
        }
        // lib.mkIf (cfg.dev.test.logdev != "") {
          "/mnt/test_logdev" = {
            device = cfg.dev.test.logdev;
            fsType = "xfs";
            options = ["nofail"];
          };
        }
        // lib.mkIf (cfg.dev.scratch.main != "") {
          "/mnt/scratch" = {
            device = cfg.dev.scratch.main;
            fsType = "xfs";
            options = ["nofail"];
          };
        }
        // lib.mkIf (cfg.dev.scratch.rtdev != "") {
          "/mnt/scratch_rtdev" = {
            device = cfg.dev.scratch.rtdev;
            fsType = "xfs";
            options = ["nofail"];
          };
        }
        // lib.mkIf (cfg.dev.scratch.logdev != "") {
          "/mnt/scratch_rtdev" = {
            device = cfg.dev.scratch.logdev;
            fsType = "xfs";
            options = ["nofail"];
          };
        };

      systemd.services.xfstests = {
        enable = true;
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal+console";
          StandardError = "journal+console";
          # argh... Nix ignore SIGPIPE somewhere and it causes all child processes
          # to ignore SIGPIPE. Don't remove it or otherwise many tests will fail
          # due too Broken pipe. Test with yes | head should not return Brokne
          # pipe.
          IgnoreSIGPIPE = "no";
          User = "root";
          Group = "root";
          WorkingDirectory = "/root";
        };
        path = [
          xfsprogs
          pkgs.e2fsprogs
        ];
        after = ["network.target" "network-online.target" "local-fs.target"];
        wants = ["network.target" "network-online.target" "local-fs.target"];
        wantedBy = ["multi-user.target"];
        postStop =
          ''
            # Beep beep... Human... back to work
            echo -ne '\007'
          ''
          + optionalString cfg.autoshutdown ''
            # Auto poweroff
            ${pkgs.systemd}/bin/systemctl poweroff;
          '';
        script = let
          mkfs-options = getAttr "${cfg.filesystem}" {
            xfs = "-f";
            ext4 = "-F";
          };
          use_external =
            if
              cfg.dev.test.rtdev
              != ""
              || cfg.dev.test.logdev != ""
              || cfg.dev.scratch.rtdev != ""
              || cfg.dev.scratch.logdev != ""
            then "yes"
            else "";
        in
          ''
            setup_log=$(mktemp)

            function get_config {
              ${pkgs.tomlq}/bin/tq --file /root/share/kd.toml $@ 2>$setup_log || true
            }

            if [ ! -f "/root/share/kd.toml" ] && [ "${cfg.arguments}" == "" ]; then
              echo "/root/share/kd.toml: file doesn't exist"
              exit 0
            fi

            if [ "$(get_config 'xfstests.args')" == "" ] && [ "${cfg.arguments}" == "" ]; then
              echo "No tests to run"
              exit 0
            fi

            arguments="$(get_config 'xfstests.args')"
            if [ "$arguments" == "" ]; then
              arguments="${cfg.arguments}"
            fi;

            test_dev="$(get_config 'xfstests.test_dev')"
            if [ "$test_dev" == "" ]; then
              test_dev="${cfg.dev.test.main}"
            fi;

            scratch_dev="$(get_config 'xfstests.scratch_dev')"
            if [ "$scratch_dev" == "" ]; then
              scratch_dev="${cfg.dev.scratch.main}"
            fi;

            # Prepare disks
            if ${pkgs.util-linux}/bin/mountpoint /mnt/test &> $setup_log; then
              ${pkgs.util-linux}/bin/umount $test_dev &> $setup_log
            fi
            if ${pkgs.util-linux}/bin/mountpoint /mnt/scratch &> $setup_log; then
              ${pkgs.util-linux}/bin/umount $scratch_dev &> $setup_log
            fi

            ${pkgs.util-linux}/bin/mkfs \
              -t ${cfg.filesystem} \
              ${mkfs-options} \
              -L test $test_dev \
              2>&1 >> $setup_log
            ${pkgs.util-linux}/bin/mkfs \
              -t ${cfg.filesystem} \
              ${mkfs-options} \
              -L scratch $scratch_dev \
              2>&1 >> $setup_log
            echo "Initial mkfs output for test/scratch can be found at $setup_log"

            export TEST_DEV="$test_dev"
            export TEST_RTDEV="${cfg.dev.test.rtdev}"
            export TEST_LOGDEV="${cfg.dev.test.logdev}"
            export SCRATCH_DEV="$scratch_dev"
            export SCRATCH_RTDEV="${cfg.dev.scratch.rtdev}"
            export SCRATCH_LOGDEV="${cfg.dev.scratch.logdev}"
            export USE_EXTERNAL="${use_external}"
            # These activates some xfsprogs maintaner tests, not strictly
            # necessary but I'm currently maintaner
            export WORKAREA=${xfsprogs.src}
            ${cfg.extraEnv}

            env_log=$(mktemp)
            env > $env_log
            echo "Environment can be found in $env_log"

            echo "xfstests config is at ${config.environment.variables.HOST_OPTIONS}"

            echo "Running:"
            echo -e "\txfstests-check $arguments"
            ${pkgs.bash}/bin/bash -lc \
              "echo $arguments | xargs ${xfstests}/bin/xfstests-check"

          ''
          + (optionalString (cfg.upload-results) ''
            ${pkgs.xfstests-upload}/bin/xfstests-upload \
              ${cfg.repository} \
              ${config.networking.hostName} \
              /root/results
          '');
      };
    };
}
