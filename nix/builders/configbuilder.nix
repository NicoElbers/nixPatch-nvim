{
  stdenvNoCC
  , lib
  , callPackage
  , writeText
}:
{
  nixpkgsOutPath # This is the magic sauce that makes the parser work
  , luaPath
  , plugins
  , name
  , withNodeJs
  , withPython3
  , withRuby
  , withPerl
}:
{ finalPackDir, extraLuaConfig ? [], customSubs ? [ ] }:
let
  hostprog_check_table = {
    node = withNodeJs;
    python = false;
    python3 = withPython3;
    ruby = withRuby;
    perl = withPerl;
  };

  genProviderCmd = prog: withProg: 
    if withProg 
    then "vim.g.${prog}_host_prog='${placeholder "out"}/bin/${name}-${prog}'"
    else "vim.g.loaded_${prog}_provider=0";

  # TODO: pass these in as extra config later
  hostProviderLua = lib.mapAttrsToList genProviderCmd hostprog_check_table;

  finalExtaConfig = builtins.concatStringsSep "\n" (
        hostProviderLua
        ++ [ "vim.g.nixos = true"]
        ++ (if (builtins.isList extraLuaConfig) then extraLuaConfig else [extraLuaConfig])
        ++ [ "\n" ]);

  finalExtaConfigEscaped = lib.escapeShellArgs [finalExtaConfig];

  # TODO: pass in a zig version here
  configPatcher = callPackage ./zigBuilder.nix { };
  configPatcherExe = lib.getExe configPatcher;

  inputBlob = lib.escapeShellArgs [(builtins.concatStringsSep ";"
    (builtins.map (plugin: "${plugin.pname}|${plugin.version}|${plugin}") plugins))];

  subBlob = lib.escapeShellArgs [(builtins.concatStringsSep ";"
    (map (s: "${s.from}|${s.to}") customSubs))];

in 
stdenvNoCC.mkDerivation {
  name = "nvim-config-patched";
  version = "0";
  src = luaPath;

  dontConfigure = true;
  dontInstall = true;

  buildPhase = /* bash */ ''
    echo "Starting patcher"
    ${configPatcherExe} ${nixpkgsOutPath} $(pwd) $out \
      ${inputBlob} \
      ${subBlob} \
      ${finalExtaConfigEscaped} \
    echo "done with patcher"

    echo "##################"
    echo "##################"
    echo "##################"
    echo "##################"
    echo $out
    echo "##################"
    echo "##################"
    echo "##################"
    echo "##################"
  '';
}
