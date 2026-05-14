{
  description = "kd - Linux Kernel development toolset";

  nixConfig = {
    extra-substituters = [
      "https://cache.alberand.com"
    ];

    extra-trusted-public-keys = [
      "cache.alberand.com:wZXao5e2MQRInFBR0GkNbwSSmIhC3maO1W7D8QPUL0o="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    rust-overlay,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        overlay
        (import rust-overlay)
      ];
    };
    overlay = import ./overlay {inherit pkgs lib;};
    lib = import ./lib.nix {
      inherit pkgs;
      inherit (nixpkgs.lib) nixosSystem;
    };
    default = lib.mkEnv {};
  in {
    inherit lib;

    overlays.default = overlay;

    devShells."${system}" = import ./devshells {inherit pkgs;};

    packages."${system}" =
      default
      // {
        kd = pkgs.callPackage (import ./kd/derivation.nix) {
          inherit (pkgs.lib) makeBinPath fileset;
        };
      };

    templates.default = {
      path = ./templates/vm;
      description = "kd kernel environment";
    };

    checks."${system}" = {
      default = pkgs.testers.runNixOSTest {
        name = "basic-test";
        nodes = {
          machine = {
            pkgs,
            config,
            ...
          }: let
            buildKernelHeaders = pkgs.makeLinuxHeaders;
            sources = pkgs.lib.importJSON ./sources/kernel.json;
          in {
            imports = [
              ./xfstests/module.nix
              ./xfsprogs/module.nix
              ./script/module.nix
              ./input.nix
              ./vm.nix
            ];

            config = {
              boot = {
                kernelModules = pkgs.lib.mkForce [];
                initrd = {
                  systemd.emergencyAccess = true;
                  # Override required kernel modules by nixos/modules/profiles/qemu-guest.nix
                  # As we use kernel build outside of Nix, it will have different uname and
                  # will not be able to find these modules. This probably can be fixed
                  availableKernelModules = pkgs.lib.mkForce [];
                  kernelModules = pkgs.lib.mkForce [];
                };
              };
              networking.hostName = "kd-test";
              kernel = {
                src = pkgs.fetchgit sources;
                version = sources.rev;
              };
              virtualisation.diskImage = "/tmp/${config.system.name}.qcow2";

              services.xfsprogs = {
                enable = true;
                kernelHeaders = buildKernelHeaders {
                  inherit (config.kernel) src version;
                };
              };
              services.xfstests = {
                enable = true;
                arguments = "-s xfs_4k generic/110 xfs/304";
                kernelHeaders = buildKernelHeaders {
                  inherit (config.kernel) src version;
                };
              };
            };
          };
        };

        testScript = ''
          machine.start()
          machine.wait_for_unit("default.target")
          machine.wait_until_fails("systemctl is-active xfstests.service")
          status = machine.succeed("systemctl show --property=ExecMainStatus xfstests.service")
          assert ' '.join(status.split()) == "ExecMainStatus=0"
        '';
      };
    };
  };
}
