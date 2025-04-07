{makeRustPlatform, rust-bin}:
let
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.nightly.latest.minimal;
    rustc = rust-bin.nightly.latest.minimal;
  };
in

rustPlatform.buildRustPackage {
  pname = "kd";
  version = "0.0.1";

  src = ./.;
  cargoHash = "sha256-XdA1j86bdHGBu4q6WuZePWSobXBLhXQwnKz/akUVR6s=";
}
