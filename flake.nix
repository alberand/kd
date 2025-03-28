{
  description = "kd - Linux Kernel development toolset";

  nixConfig = {
    # override the default substituters
    # TODO this need to be replaced with public bucket or something
    extra-substituters = [
      "http://192.168.0.100"
    ];

    extra-trusted-public-keys = [
      "192.168.0.100:T4If+3X03bZC62Jh+Uzuz+ElERtgQFlbarUQE1PzC94="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nixos-generators,
  }:
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux"] (system: let
      pkgs = import nixpkgs {
        inherit system;
        oerlays = [
          (_final: prev: {
            xfstests-configs = (import ./xfstests/configs.nix) {pkgs = prev;};
          })
        ];
      };
      lib = import ./lib.nix {
        inherit pkgs nixos-generators;
      };
      default = lib.mkEnv {
        name = "demo";
        root = builtins.toString ./.;
        stdenv = pkgs.clangStdenv;
      };
    in {
      devShells.default = default.shell;

      packages = {
        inherit (default) kconfig kconfig-iso headers kernel iso vm;
      };

      templates.default = {
        path = ./templates/vm;
      };
    });
}
