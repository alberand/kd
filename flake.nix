{
  description = "kd - Linux Kernel development toolset";

  # nixConfig = {
  # override the default substituters
  # TODO this need to be replaced with public bucket or something
  # extra-substituters = [
  # "http://192.168.0.100"
  # ];

  # extra-trusted-public-keys = [
  # "192.168.0.100:T4If+3X03bZC62Jh+Uzuz+ElERtgQFlbarUQE1PzC94="
  # ];
  # };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-clang.url = "github:nixos/nixpkgs/6915a163f351c32bd4557518d047725665e83d37";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-clang,
    flake-utils,
    nixos-generators,
    rust-overlay,
  }:
    flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
      pkgs-clang = import nixpkgs-clang {
        inherit system;
      };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (import rust-overlay)
          (final: prev: {
            llvmPackages_latest = pkgs-clang.llvmPackages_latest;
          })
        ];
      };
      specialArgs = {
        inherit pkgs-clang pkgs;
      };
      lib = import ./lib.nix {
        inherit pkgs nixos-generators nixpkgs;
      };
      default = lib.mkEnv {
        inherit nixpkgs;
        name = "demo";
        root = builtins.toString ./.;
      };
    in {
      inherit lib;

      devShells = {
        default = default.shell;
        clang = default.shell;
        clang20 = default.shell-clang20;
        clang18 = default.shell-clang18;
        clang17 = default.shell-clang17;
        gcc = default.shell-gcc;
        gcc15 = default.shell-gcc15;
        gcc14 = default.shell-gcc14;
        gcc13 = default.shell-gcc13;

        xfsprogs = lib.mkXfsprogsShell {};
        xfstests = lib.mkXfstestsShell {};

        kd-dev = with pkgs;
          mkShell {
            buildInputs = [
              cargo
              rustc
              pkg-config
              openssl
              rust-analyzer
              rustfmt
            ];
          };
      };

      packages =
        default
        // {
          kd = pkgs.callPackage (import ./kd/derivation.nix) {};
        };

      templates.default = {
        path = ./templates/vm;
      };

      checks = {
        "${system}".default = pkgs.testers.runNixOSTest {
          name = "basic-test";
          nodes = {
            machine = {pkgs, ...}: {
              imports = [
                (import ./xfstests/module.nix {})
                (import ./xfsprogs/module.nix {})
                ./script/module.nix
                ./system.nix
                (pkgs.callPackage (import ./input.nix) {inherit nixpkgs;})
                ({config, ...}: let
                  buildKernelHeaders = pkgs.makeLinuxHeaders;
                  sources = pkgs.lib.importJSON ./sources/kernel.json;
                in {
                  networking.hostName = "kd-test";
                  kernel = {
                    src = pkgs.fetchgit sources;
                    version = sources.rev;
                  };
                  vm.workdir = "/tmp/kd-test/";
                  vm.disks = [12000 12000 2000 2000];

                  services.xfsprogs = {
                    enable = true;
                    kernelHeaders = buildKernelHeaders {
                      inherit (config.kernel) src version;
                    };
                  };
                  services.script = {
                    enable = true;
                  };
                  services.xfstests = {
                    enable = true;
                    test-dev = pkgs.lib.mkDefault "/dev/vdb";
                    scratch-dev = pkgs.lib.mkDefault "/dev/vdc";
                    arguments = "-R xunit -s xfs_4k generic/110";
                    kernelHeaders = buildKernelHeaders {
                      inherit (config.kernel) src version;
                    };
                  };
                })
              ];
              environment.systemPackages = [pkgs.curl];
            };
          };

          testScript = ''
            machine.start()
            machine.wait_for_unit("xfstests")
            status = machine.succeed("systemctl show --property=ExecMainStatus xfstests.service")
            assert status == "ExecMainStatus=1"
          '';
        };
      };
    });
}
