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
    zig build --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
      -Dcpu=baseline \
      --prefix $out 
  '';
      # TODO: Add this back later
      # -Doptimize=ReleaseSafe \

  checkPhase = ''
    echo "Running zig tests"
    zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache \
      -Dcpu=baseline 
    echo "Done running tests"
  '';

  meta.mainProgram = "config-patcher";
}
