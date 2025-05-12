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
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    nixos-generators,
    rust-overlay,
  }:
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux"] (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (_final: prev: {
            xfstests-configs = (import ./xfstests/configs.nix) {pkgs = prev;};
          })
          (import rust-overlay)
        ];
      };
      lib = import ./lib.nix {
        inherit pkgs nixos-generators nixpkgs;
      };
      default = lib.mkEnv {
        inherit nixpkgs;
        name = "demo";
        root = builtins.toString ./.;
        stdenv = pkgs.clangStdenv;
      };
    in {
      inherit lib;

      devShells = {
        default = default.shell;
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

      packages = {
        inherit
          (default)
          kconfig
          kconfig-iso
          headers
          kernel
          iso
          vm
          qcow
          prebuild
          ;
      };

      templates.default = {
        path = ./templates/vm;
      };
    });
}
