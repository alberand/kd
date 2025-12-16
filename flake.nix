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
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-clang,
    nixos-generators,
    rust-overlay,
  }: let
    system = "x86_64-linux";
    overlay = final: prev: {
      kconfigs = import ./kconfigs/default.nix {inherit (pkgs) lib;};
    };
    pkgs-clang = import nixpkgs-clang {
      inherit system;
    };
    pkgs = import nixpkgs {
      inherit system;
      overlays = [
        (final: prev: {
          llvmPackages_latest = pkgs-clang.llvmPackages_latest;
        })
        overlay
        (import ./xfstests/overlay.nix)
        (import ./xfsprogs/overlay.nix)
      ];
    };
    lib = import ./lib.nix {
      inherit pkgs nixos-generators nixpkgs;
    };
    default = lib.mkEnv {
      inherit nixpkgs;
    };
  in {
    inherit lib;

    overlays.default = overlay;

    devShells."${system}" = {
      default = default.shell;
      clang = default.shell;
      clang20 = default.shell-clang20;
      clang18 = default.shell-clang18;
      gcc = default.shell-gcc;
      gcc15 = default.shell-gcc15;
      gcc14 = default.shell-gcc14;
      gcc13 = default.shell-gcc13;

      xfsprogs = lib.mkXfsprogsShell {};
      xfstests = lib.mkXfstestsShell {};

      kd-dev = let
        rust-pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import rust-overlay)
          ];
        };
      in
        rust-pkgs.mkShell {
          buildInputs = with rust-pkgs; [
            cargo
            rustc
            pkg-config
            openssl
            rust-analyzer
            rustfmt
          ];
        };
    };

    packages."${system}" =
      default
      // {
        kd = pkgs.callPackage (import ./kd/derivation.nix) {
          inherit (pkgs.lib) makeBinPath;
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
              services.xfstests = {
                enable = true;
                dev = {
                  test = pkgs.lib.mkDefault "/dev/vdb";
                  scratch = pkgs.lib.mkDefault "/dev/vdc";
                };
                arguments = "-s xfs_4k -s ext4_4k generic/110";
                kernelHeaders = buildKernelHeaders {
                  inherit (config.kernel) src version;
                };
              };
              environment.systemPackages = [pkgs.curl];
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
