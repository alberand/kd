{enableCcache ? false}: {
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
      type = types.nullOr types.package;
      description = "Linux kernel headers to compile xfstests against";
      default = null;
    };
  };

  config = mkIf cfg.enable {
    warnings = (
      lib.optionals (cfg.upload-results && (cfg.repository == ""))
      "To upload results set services.xfstests.repository"
    );

    nixpkgs.overlays = [
      (
        final: prev: {
          xfstests = prev.xfstests.overrideAttrs (old: ({
              inherit (cfg) src;
              version = "git-${cfg.src.rev}";

              nativeBuildInputs =
                old.nativeBuildInputs
                ++ prev.lib.optionals (cfg.kernelHeaders != null) [cfg.kernelHeaders];

              dontStrip = config.dev.dontStrip;
            }
            // prev.lib.optionalAttrs enableCcache {
              stdenv = prev.ccacheStdenv;
            }));
        }
      )
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
        pkgs.xfsprogs
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
      in
        ''
          function get_config {
            ${pkgs.tomlq}/bin/tq --file /root/share/kd.toml $@ || true
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
            test_dev="${cfg.test-dev}"
          fi;

          scratch_dev="$(get_config 'xfstests.scratch_dev')"
          if [ "$scratch_dev" == "" ]; then
            scratch_dev="${cfg.scratch-dev}"
          fi;

          # Prepare disks
          mkfs_initial=$(mktemp)
          if ${pkgs.util-linux}/bin/mountpoint /mnt/test; then
            ${pkgs.util-linux}/bin/umount $test_dev 2>&1 >> $mkfs_initial
          fi
          if ${pkgs.util-linux}/bin/mountpoint /mnt/scratch; then
            ${pkgs.util-linux}/bin/umount $scratch_dev 2>&1 >> $mkfs_initial
          fi

          ${pkgs.util-linux}/bin/mkfs \
            -t ${cfg.filesystem} \
            ${mkfs-options} \
            -L test $test_dev \
            2>&1 >> $mkfs_initial
          ${pkgs.util-linux}/bin/mkfs \
            -t ${cfg.filesystem} \
            ${mkfs-options} \
            -L scratch $scratch_dev \
            2>&1 >> $mkfs_initial
          echo "Initial mkfs output for test/scratch can be found at $mkfs_initial"

          export TEST_DEV="$test_dev"
          export SCRATCH_DEV="$scratch_dev"
          ${cfg.extraEnv}
          ${pkgs.bash}/bin/bash -lc \
            "${pkgs.xfstests}/bin/xfstests-check $arguments"

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
