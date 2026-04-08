{
  rustPlatform,
  nurl,
  pkg-config,
  openssl,
  makeBinPath,
  makeWrapper,
  nix,
  gitMinimal,
  alejandra,
  openssh,
  fileset,
  installShellFiles
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
      installShellFiles
    ];
    buildInputs = [
      openssl
    ];

    # installManPage man/man1/kd.1
    # installManPage man/man5/kd.5
    postInstall = ''
      installShellCompletion --bash $src/completions/kd.bash
      installShellCompletion --fish $src/completions/kd.fish
      installShellCompletion --zsh $src/completions/_kd
    '';

    postFixup = ''
      wrapProgram $out/bin/kd \
        --set PATH ${
        makeBinPath [
          gitMinimal
          openssh
          nurl
          nix
          alejandra
        ]
      }
    '';
  }
