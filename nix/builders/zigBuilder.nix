{ lib, stdenvNoCC, zig_0_14 }:
stdenvNoCC.mkDerivation {
  pname = "config-patcher";
  version = "0";

  src = lib.sources.sourceByRegex (lib.cleanSource ../../.) [".*patcher.*"];

  nativeBuildInputs = [ zig_0_14 ];

  dontConfigure = true;
  dontInstall = true;
  doCheck = true;

  buildPhase = ''
    mkdir -p .cache

    # Explicitly a debug build, since it cuts total build time by abt 10 seconds
    zig build-exe \
        -ODebug \
        --dep lib \
        -Mroot=$(pwd)/patcher/src/main.zig \
        -ODebug \
        -Mlib=$(pwd)/patcher/src/lib/root.zig \
        --cache-dir $(pwd)/.zig-cache \
        --global-cache-dir $(pwd)/.cache \
        --name config-patcher

    mkdir -p $out/bin
    cp config-patcher $out/bin
  '';

  checkPhase = ''
    zig test \
        -ODebug \
        --dep lib \
        -Mroot=$(pwd)/patcher/test/root.zig \
        -ODebug \
        -Mlib=$(pwd)/patcher/src/lib/root.zig \
        --cache-dir $(pwd)/.zig-cache \
        --global-cache-dir $(pwd)/.cache \
        --name test

    zig test \
        -ODebug \
        --dep lib \
        -Mroot=$(pwd)/patcher/src/lib/root.zig \
        -ODebug \
        -Mlib=$(pwd)/patcher/src/lib/root.zig \
        --cache-dir $(pwd)/.zig-cache \
        --global-cache-dir $(pwd)/.cache \
        --name test
  '';

  meta.mainProgram = "config-patcher";
}
