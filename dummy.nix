{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config.services.dummy;
in {
  options.services.dummy = {
    enable = mkEnableOption {
      name = "dummy";
      default = true;
      example = true;
    };

    arguments = mkOption {
      description = "arguments to the test script";
      default = "";
      example = "-f hello";
      type = types.str;
    };

    autoshutdown = mkOption {
      description = "autoshutdown machine after test is complete";
      default = false;
      example = false;
      type = types.bool;
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /mnt 1777 root root"
      "d /mnt/test 1777 root root"
    ];

    systemd.services.dummy = {
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
          # Beep beep... Human... back to work
          echo -ne '\007'
        ''
        + optionalString cfg.autoshutdown ''
          # Auto poweroff
          ${pkgs.systemd}/bin/systemctl poweroff;
        '';
      script = ''
        function get_config {
          ${pkgs.tomlq}/bin/tq --file /root/share/kd.toml $@
        }

        if [ ! -f "/root/share/kd.toml" ]; then
          exit 0
        fi

        if [ "$(get_config 'dummy')" == "" ]; then
          exit 0
        fi

        echo "Running test /root/share/dummy.sh"
        chmod u+x /root/share/dummy.sh
        ${pkgs.bash}/bin/bash -l -c 'exec /root/share/dummy.sh ${cfg.arguments}'
        exit $?
      '';
    };
  };
}
