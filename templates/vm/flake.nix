{
  description = "Linux Kernel development environment";

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
        overlays = [kd.overlays.default];
      };
      packages = let
        uset = import ./uconfig.nix;
      in
        kd.lib.mkEnv {
          inherit nixpkgs;
          uconfig = uset.uconfig {inherit pkgs kd;};
        };
    in {
      inherit packages;
      devShells = {
        default = packages.shell;
      };
    });
}
