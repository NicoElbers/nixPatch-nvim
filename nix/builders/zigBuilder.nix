{ lib, stdenvNoCC, zig }:
stdenvNoCC.mkDerivation {
  pname = "config-patcher";
  version = "0";

  src = lib.sources.sourceByRegex (lib.cleanSource ../../.) ["build.zig" ".*patcher.*"];

  nativeBuildInputs = [ zig ];

  dontConfigure = true;
  dontInstall = true;
  doCheck = true;

  buildPhase = ''
    mkdir -p .cache

    # Not using the build script is significantly faster, but the convenience
    # of not having to change the command every time I would add/ remove a module
    # or test, is fantastic
    zig build --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
      -Dcpu=baseline \
      --verbose \
      --prefix $out 
  '';

  checkPhase = ''
    echo "Running zig tests"

    # Not using the build script is significantly faster, but the convenience
    # of not having to change the command every time I would add/ remove a module
    # or test, is fantastic
    zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
      --verbose \
      -Dcpu=baseline 

    echo "Done running zig tests"
  '';

  meta.mainProgram = "config-patcher";
}
