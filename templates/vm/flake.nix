{
  description = "Linux Kernel development environment";

  nixConfig = {
    extra-substituters = [
      "https://kd.cachix.org"
    ];

    extra-trusted-public-keys = [
      "kd.cachix.org-1:bm6NSngyz8Ncm+S1FhKWvSq7XQWIc34Kab656Jhhlxc="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
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
        ++ nixpkgs.lib.optional (builtins.pathExists ./overlays.nix) (import ./overlays.nix);
    };
    packages = kd.lib.mkEnv {
      inherit pkgs;
      user-modules =
        [
          (import ./uconfig.nix)
        ]
        ++ (pkgs.lib.optional (builtins.pathExists ./modules.nix) ./modules.nix);
    };
  in {
    packages.${system} = packages;
    devShells.${system} = {
      default = kd.devShells.${system}.default;
    };
  };
}
