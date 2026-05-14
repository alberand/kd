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
    kd.url = "github:alberand/kd";
  };
  outputs = {
    self,
    nixpkgs,
    kd,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays =
        [
          kd.overlays.default
        ]
        ++ pkgs.lib.optional (builtins.pathExists ./overlays.nix) (import ./overlays.nix);
    };
    packages = kd.lib.mkEnv {
      user-modules =
        [
          (import ./uconfig.nix)
        ]
        ++ (pkgs.lib.optional (builtins.pathExists ./modules.nix) ./modules.nix);
    };
  in {
    packages.${system} = packages;
    devShells.${system} = {
      default = packages.shell;
    };
  };
}
