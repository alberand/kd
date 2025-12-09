{
  rustPlatform,
  nurl,
  pkg-config,
  openssl,
  makeBinPath,
  makeWrapper,
  nix,
}:
rustPlatform.buildRustPackage {
  pname = "kd";
  version = "0.0.1";

  src = ./.;
  cargoHash = "sha256-uUQFZHOletypATpLvk4BSWilFKjHoYP8SfR7ryZWUUQ=";
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
        nurl
        nix
      ]
    }
  '';
}
