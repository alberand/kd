{
  description = "Linux Kernel development environment";

  nixConfig = {
    # override the default substituters
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
    kd.url = "github:alberand/kd";
    kd.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    kd,
  }:
    flake-utils.lib.eachDefaultSystem (_: let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
      };
      vm = let
        uset = (import ./uconfig.nix);
      in
        kd.lib.${system}.mkEnv {
          inherit nixpkgs;
          inherit (uset) name;
          root = builtins.toString ./.;
          stdenv = pkgs.clangStdenv;
          uconfig = uset.uconfig {inherit pkgs;};
        };
    in {
      packages = {
        inherit (vm) kconfig kconfig-iso headers kernel iso vm qcow prebuild;
      };
      devShells = {
        default = vm.shell;
      };
    });
}
