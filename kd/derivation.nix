{
  rustPlatform,
  nurl,
  pkg-config,
  openssl,
}:
rustPlatform.buildRustPackage {
  pname = "kd";
  version = "0.0.1";

  src = ./.;
  cargoHash = "sha256-uUQFZHOletypATpLvk4BSWilFKjHoYP8SfR7ryZWUUQ=";
  nativeBuildInputs = [
    pkg-config
    nurl
  ];
  buildInputs = [
    openssl
  ];

  PATH = "$PATH:${nurl}/bin";
}
