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
  cargoHash = "sha256-XdA1j86bdHGBu4q6WuZePWSobXBLhXQwnKz/akUVR6s=";
  nativeBuildInputs = [
    pkg-config
    nurl
  ];
  buildInputs = [
    openssl
  ];
}
