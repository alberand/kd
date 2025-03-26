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
      vm = kd.lib.${system}.mkEnv {
        name = "wowo";
        root = builtins.toString ./.;
        sources = import ./system.nix;
      };
    in {
      packages = {
        inherit (vm) kconfig kconfig-iso headers kernel iso vm;
      };
      devShells = {
        default = vm.shell;
      };
    });
}
