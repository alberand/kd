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
  cargoHash = "sha256-T6PaII+HU/ZQn0n4iJDucY2CJpdATiSWkLEAZ9X/wQw=";
  nativeBuildInputs = [
    pkg-config
    nurl
  ];
  buildInputs = [
    openssl
  ];
}
