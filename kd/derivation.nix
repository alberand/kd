{
  rustPlatform,
  nurl,
  pkg-config,
  openssl,
  makeBinPath,
  makeWrapper,
  nix,
  gitMinimal,
  openssh,
  fileset,
}: let
  sourceFiles = fileset.difference ./. (
    fileset.unions [
      (fileset.maybeMissing ./result)
      (fileset.maybeMissing ./target)
    ]
  );
in
  rustPlatform.buildRustPackage {
    pname = "kd";
    version = "0.0.1";

    src = fileset.toSource {
      root = ./.;
      fileset = sourceFiles;
    };
    cargoLock = {
      lockFile = ./Cargo.lock;
    };
    nativeBuildInputs = [
      pkg-config
      makeWrapper
    ];
    buildInputs = [
      openssl
    ];

    postFixup = ''
      wrapProgram $out/bin/kd \
        --set PATH ${
        makeBinPath [
          gitMinimal
          openssh
          nurl
          nix
        ]
      }
    '';
  }
