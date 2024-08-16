{ lib
, stdenv
, cmake
, libGLU
, libGL
, zlib
, wxGTK
, gtk3
, libX11
, gettext
, glew
, glm
, cairo
, curl
, openssl
, boost
, pkg-config
, doxygen
, graphviz
, pcre
, libpthreadstubs
, libXdmcp
, unixODBC
, libgit2
, libsecret
, libgcrypt
, libgpg-error
, fontconfig

, util-linux
, libselinux
, libsepol
, libthai
, libdatrie
, libxkbcommon
, libepoxy
, dbus
, at-spi2-core
, libXtst
, pcre2
, libdeflate

, swig4
, python
, wxPython
, opencascade-occt_7_6
, libngspice
, valgrind
, protobuf

, stable
, testing
, baseName
, kicadSrc
, kicadVersion
, withNgspice
, withScripting
, withI18n
, debug
, sanitizeAddress
, sanitizeThreads
}:

assert lib.assertMsg (!(sanitizeAddress && sanitizeThreads))
  "'sanitizeAddress' and 'sanitizeThreads' are mutually exclusive, use one.";
assert testing -> !stable
  -> throw "testing implies stable and cannot be used with stable = false";

let
  opencascade-occt = opencascade-occt_7_6;
  inherit (lib) optional optionals optionalString;
  needsProtobuf = !stable && !testing;
in
stdenv.mkDerivation rec {
  pname = "kicad-base";
  version = if (stable) then kicadVersion else builtins.substring 0 10 src.rev;

  src = kicadSrc;

  patches = [
    # upstream issue 12941 (attempted to upstream, but appreciably unacceptable)
    ./writable.patch
    # https://gitlab.com/kicad/code/kicad/-/issues/15687
    ./runtime_stock_data_path.patch
  ];

  postPatch = lib.concatStrings (
    # tagged releases don't have "unknown"
    # kicad testing and nightlies use git describe --dirty
    # nix removes .git, so its approximated here
    lib.optional (!stable || testing) ''
    substituteInPlace cmake/KiCadVersion.cmake \
      --replace "unknown" "${builtins.substring 0 10 src.rev}"

    substituteInPlace cmake/CreateGitVersionHeader.cmake \
      --replace "0000000000000000000000000000000000000000" "${src.rev}"
    '' ++
    # unstable is failing testing:
    # Fontconfig error: Cannot load default config file: No such file: (null)
    lib.optional (!stable && !testing) ''
    rm qa/tests/cli/test_sch.py
    ''
  );

  makeFlags = optionals (debug) [ "CFLAGS+=-Og" "CFLAGS+=-ggdb" ];

  cmakeFlags = [
    "-DKICAD_USE_EGL=ON"
    "-DOCC_INCLUDE_DIR=${opencascade-occt}/include/opencascade"
    # https://gitlab.com/kicad/code/kicad/-/issues/17133
    "-DCMAKE_CTEST_ARGUMENTS='--exclude-regex;qa_spice'"
  ]
  ++ optional needsProtobuf "-DProtobuf_DIR=${protobuf}"
  ++ optional (stdenv.hostPlatform.system == "aarch64-linux")
    "-DCMAKE_CTEST_ARGUMENTS=--exclude-regex;'qa_spice|qa_cli'"
  ++ optional (stable && !withNgspice) "-DKICAD_SPICE=OFF"
  ++ optionals (!withScripting) [
    "-DKICAD_SCRIPTING_WXPYTHON=OFF"
  ]
  ++ optionals (withI18n) [
    "-DKICAD_BUILD_I18N=ON"
  ]
  ++ optionals (!doInstallCheck) [
    "-DKICAD_BUILD_QA_TESTS=OFF"
  ]
  ++ optionals (debug) [
    "-DKICAD_STDLIB_DEBUG=ON"
    "-DKICAD_USE_VALGRIND=ON"
  ]
  ++ optionals (sanitizeAddress) [
    "-DKICAD_SANITIZE_ADDRESS=ON"
  ]
  ++ optionals (sanitizeThreads) [
    "-DKICAD_SANITIZE_THREADS=ON"
  ];

  cmakeBuildType = if debug then "Debug" else "Release";

  nativeBuildInputs = [
    cmake
    doxygen
    graphviz
    pkg-config
    libgit2
    libsecret
    libgcrypt
    libgpg-error
  ]
  ++ optional needsProtobuf protobuf
  # wanted by configuration on linux, doesn't seem to affect performance
  # no effect on closure size
  ++ optionals (stdenv.isLinux) [
    util-linux
    libselinux
    libsepol
    libthai
    libdatrie
    libxkbcommon
    libepoxy
    dbus
    at-spi2-core
    libXtst
    pcre2
  ];

  buildInputs = [
    libGLU
    libGL
    zlib
    libX11
    wxGTK
    gtk3
    pcre
    libXdmcp
    gettext
    glew
    glm
    libpthreadstubs
    cairo
    curl
    openssl
    boost
    swig4
    python
    unixODBC
    libdeflate
    opencascade-occt
  ]
  ++ optional needsProtobuf protobuf
  ++ optional (withScripting) wxPython
  ++ optional (withNgspice) libngspice
  ++ optional (debug) valgrind;

  # some ngspice tests attempt to write to $HOME/.cache/
  # this could be and was resolved with XDG_CACHE_HOME = "$TMP";
  # but failing tests still attempt to create $HOME
  # and the newer CLI tests seem to also use $HOME...
  HOME = "$TMP";

  # debug builds fail all but the python test
  # FIXME: Is it still problem
  doInstallCheck = !debug;
  installCheckTarget = "test";

  nativeInstallCheckInputs = [
    (python.withPackages(ps: with ps; [
      numpy
      pytest
      cairosvg
      pytest-image-diff
    ]))
  ];

  dontStrip = debug;

  meta = {
    description = "Just the built source without the libraries";
    longDescription = ''
      Just the build products, the libraries are passed via an env var in the wrapper, default.nix
    '';
    homepage = "https://www.kicad.org/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
  };
}
