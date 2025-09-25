{
  description = "Linux Kernel development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
        overlays = [kd.overlays.x86_64-linux.default];
      };
      packages = let
        uset = import ./uconfig.nix;
      in
        kd.lib.${system}.mkEnv {
          inherit nixpkgs;
          inherit (uset) name;
          root = builtins.toString ./.;
          uconfig = uset.uconfig {inherit pkgs;};
        };
    in {
      inherit packages;
      devShells = {
        default = packages.shell;
      };
    });
}
