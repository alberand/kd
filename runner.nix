{
  nixos,
  lib,
  makeWrapper,
  runCommand,
  bash,
  coreutils-full,
  tomlq
}:

let
  src = ./runner.sh;
  binName = "runner";
  deps = [
    bash
    tomlq
    coreutils-full
  ];
in
runCommand "${binName}"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      mainProgram = "${binName}";
    };
    NIXOS_QEMU = nixos;
  }
  ''
    mkdir -p $out/bin
    install -m +x ${src} $out/bin/${binName}

    wrapProgram $out/bin/${binName} \
      --prefix PATH : ${lib.makeBinPath deps}
  ''
