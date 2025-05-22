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
  cargoHash = "sha256-2ArjfJPc0Xi7B2bcW63YeUmdQaHej71sZS4OqS8j6wY=";
  nativeBuildInputs = [
    pkg-config
    nurl
  ];
  buildInputs = [
    openssl
  ];
}
