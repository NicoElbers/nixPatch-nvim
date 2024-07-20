{ stdenvNoCC, zig }:
stdenvNoCC.mkDerivation {
  pname = "zig-config-patcher";
  version = "0";

  src = ../..;

  nativeBuildInputs = [ zig ];

  dontConfigure = true;
  dontInstall = true;
  doCheck = true;

  # TODO: See if it's faster to just do zig build-exe
  buildPhase = ''
    mkdir -p .cache

    # Not using the build script is significantly faster
    # zig build --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
    #   -Dcpu=baseline \
    #   --verbose \
    #   --prefix $out 

    zig build-exe --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
      -ODebug \
      -target native-native \
      -mcpu baseline \
      -Mroot=$(pwd)/src/main.zig \
      --name config-patcher

    # build-exe doesn't support putting the result in an arbitrary location
    mkdir -p $out/bin
    cp config-patcher $out/bin

  '';

  checkPhase = ''
    echo "Running zig tests"

    # Not using the build script is significantly faster
    # zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
    #   --verbose \
    #   -Dcpu=baseline 

    zig test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
      -ODebug \
      -target native-native \
      -mcpu baseline \
      -Mroot=$(pwd)/src/main.zig \
      --name test

    echo "Done running tests"
  '';

  meta.mainProgram = "config-patcher";
}
