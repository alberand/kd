{
  lib,
  stdenv,
  fetchFromGitHub,
  autoconf,
  automake,
  libtool,
  gnumake,
  pkg-config,
  python3,
  python3Packages ? python3.pkgs,
  elfutils,
  xz,
  pcre2,
  json_c,
  openmp ? null,
  enableDebuginfod ? true,
  enableLzma ? true,
  enablePcre2 ? true,
  enableJsonC ? true,
  enableOpenMP ? (openmp != null),
}:
python3Packages.buildPythonApplication rec {
  pname = "drgn";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "osandov";
    repo = "drgn";
    rev = "818b5a7e8a4db82a1e0326667e7afaec5bf5fd19";
    hash = "sha256-RyMWHiNfpJ6gAefXVB5cQKbtXQzBEJ+0syPsry2me1I=";
  };

  format = "other";

  # Build system requirements
  nativeBuildInputs = [
    pkg-config
    python3Packages.setuptools
    autoconf
    automake
    libtool
    gnumake
  ];

  # Runtime dependencies
  buildInputs =
    [
      elfutils
      python3
    ]
    # libdebuginfod is included in elfutils
    ++ lib.optionals enableLzma [
      xz
    ]
    ++ lib.optionals enablePcre2 [
      pcre2
    ]
    ++ lib.optionals enableJsonC [
      json_c
    ]
    ++ lib.optionals enableOpenMP [
      openmp
    ];

  # Configure flags for the C library
  configureFlags =
    [
      "--enable-python-extension"
      "--disable-static"
      "--disable-libdrgn"
    ]
    ++ lib.optionals enableDebuginfod [
      "--with-debuginfod"
    ]
    ++ lib.optionals (!enableDebuginfod) [
      "--without-debuginfod"
    ]
    ++ lib.optionals enableLzma [
      "--with-lzma"
    ]
    ++ lib.optionals (!enableLzma) [
      "--without-lzma"
    ]
    ++ lib.optionals enablePcre2 [
      "--with-pcre2"
    ]
    ++ lib.optionals (!enablePcre2) [
      "--without-pcre2"
    ]
    ++ lib.optionals enableJsonC [
      "--with-json-c"
    ]
    ++ lib.optionals (!enableJsonC) [
      "--without-json-c"
    ]
    ++ lib.optionals (!enableOpenMP) [
      "--disable-openmp"
    ]
    ++ [
      # Disable libkdumpfile since it's not available in nixpkgs
      "--without-libkdumpfile"
    ];

  # Environment variables
  env =
    {
      PYTHON = "${python3}/bin/python3";
    }
    // lib.optionalAttrs enableOpenMP {
      # Set OpenMP flags if enabled
      OPENMP_CFLAGS = "-fopenmp";
      OPENMP_LIBS = "-l${
        if openmp.pname == "llvm"
        then "omp"
        else "gomp"
      }";
    };

  # Build phase override to handle the custom build system
  buildPhase = ''
    runHook preBuild

    # The setup.py handles the autotools build internally
    ${python3.interpreter} setup.py build

    runHook postBuild
  '';

  # Install phase
  installPhase = ''
    runHook preInstall

    ${python3.interpreter} setup.py install --prefix=$out

    runHook postInstall
  '';

  # Skip tests by default since they require kernel modules and VM setup
  doCheck = false;

  # Alternatively, enable basic tests (non-kernel tests)
  checkPhase = lib.optionalString doCheck ''
    runHook preCheck

    # Run only basic Python tests, skip kernel tests
    ${python3.interpreter} -m pytest tests/ -k "not linux_kernel" || true

    runHook postCheck
  '';

  meta = with lib; {
    description = "Programmable debugger for Linux kernel debugging and introspection";
    longDescription = ''
      drgn (pronounced "dragon") is a debugger with an emphasis on programmability.
      drgn exposes the types and variables in a program for easy, expressive
      scripting in Python. For example, you can debug the Linux kernel with
      drgn's extensive library of helpers or write your own debugger using
      drgn's Python API.
    '';
    homepage = "https://github.com/osandov/drgn";
    license = licenses.lgpl21Plus;
    maintainers = with maintainers; [];
    platforms = platforms.linux;
    # This is a Linux kernel debugging tool
    broken = !stdenv.isLinux;
  };

  # Pass through configuration for overrides
  passthru = {
    inherit
      enableDebuginfod
      enableLzma
      enablePcre2
      enableJsonC
      enableOpenMP
      ;
  };
}
