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
  cargoHash = "sha256-81umLjXpcGrjfD/wwCHVcaiVF1o/ju777DtfPN6LGPc=";
  nativeBuildInputs = [
    pkg-config
    nurl
  ];
  buildInputs = [
    openssl
  ];
}
