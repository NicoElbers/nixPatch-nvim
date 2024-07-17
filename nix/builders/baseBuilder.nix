{
  # We require nixpkgs because the wrapper parses it later
  nixpkgs
  , system
  , dependencyOverlays
}:
# TODO: Get specialArgs to work
{ configuration, specialArgs ? null, extra_pkg_config ? {} }:
let
  utils = import ../utils;

  name = "nv-test";

  pkgs = import nixpkgs ({
    inherit system;
    overlays = if builtins.isList dependencyOverlays
        then dependencyOverlays
        else if builtins.isAttrs dependencyOverlays && builtins.hasAttr system dependencyOverlays
        then dependencyOverlays.${system}
        else [];
  } // { config = extra_pkg_config; });
  lib = pkgs.lib;
  
  nixpkgsOutPath = nixpkgs.outPath;

  rawconfiguration = configuration { inherit pkgs; };

  finalConfiguration = {
    # luaPath cannot be merged
    plugins = [ ];
    aliases = [ ];
    runtimeDeps = [ ];
    environmentVariables = { };
    extraWrapperArgs = [ ];

    extraPython3Packages = [ ];
    extraPython3WrapperArgs = [ ];

    extraLuaPackages = [ ];

    propagatedBuildInputs = [ ];
    sharedLibraries = [ ];
  } 
  // rawconfiguration;

  finalSettings = {
    withNodeJs = false;
    withRuby = false;
    withPerl = false;
    withPython3 = false;
    extraName = "";
    configDirName = "nvim";
    aliases = null;
    neovim-unwrapped = null;

    suffix-path = false;
    suffix-LD = false;
    disablePythonSafePath = false;
  }
  // rawconfiguration.settings
  # TODO: Make wrapRc optional by adding an option to put
  # config in xdg.config
  // { wrapRc = true; };

  inherit (finalConfiguration) 
    luaPath plugins runtimeDeps 
    environmentVariables extraPython3Packages 
    extraPython3WrapperArgs extraLuaPackages 
    extraWrapperArgs sharedLibraries;

  inherit (finalSettings)
    withNodeJs withRuby withPerl withPython3
    extraName configDirName aliases 
    neovim-unwrapped suffix-path
    suffix-LD disablePythonSafePath wrapRc;

  python3WrapperArgs = extraPython3WrapperArgs ++ (if disablePythonSafePath then ["--unset PYTHONSAFEPATH"] else []);

  neovim = if neovim-unwrapped == null then pkgs.neovim-unwrapped else neovim-unwrapped;

  # TODO: pass in zig version here
  luaConfig = pkgs.callPackage ./configbuilder.nix { } {
    inherit luaPath nixpkgsOutPath plugins name;
    inherit withNodeJs withPerl withPython3 withRuby;
  };

  extraMakeWrapperArgs = 
    let
      pathAdditionLocation = if suffix-path then "suffix" else "prefix";
      linkableAdditionLocation = if suffix-LD then "suffix" else "prefix";

      flattenEnv = utils.flattenMapAttrLeaves (n: v: ''--set ${n} "${v}"'');
    in
    (if configDirName != null && configDirName != "" 
      then [ "--set" "NVIM_APPNAME" "${configDirName}" ] 
      else []
    )
    ++ (if runtimeDeps != [] 
      then [ "--${pathAdditionLocation}" "PATH" ":" "${pkgs.lib.makeBinPath runtimeDeps}" ] 
      else []
    )
    ++ (if sharedLibraries != [] 
      then [ "--${linkableAdditionLocation}" "LD_LIBRARY_PATH" ":" "${pkgs.lib.makeLibarryPath sharedLibraries}" ] 
      else []
    )
    ++ (pkgs.lib.unique (flattenEnv environmentVariables))
    ++ extraWrapperArgs;

  # removed rc gen from neovimMakeConfig and inlinined it:
  # https://github.com/NixOS/nixpkgs/blob/287ca00c3e9e0cc8112a38dde991966cebf896a8/pkgs/applications/editors/neovim/utils.nix#L26-L122
  rubyEnv = pkgs.bundlerEnv {
    name = "neovim-ruby-env";
    gemdir = ./ruby_provider;
    postBuild = ''
      ln -sf ${pkgs.ruby}/bin/* $out/bin
    '';
  };

  perlEnv = pkgs.perl.withPackages (p: [ p.NeovimExt p.Appcpanminus ]);

  pluginPython3Packages = utils.getDeps "python3Dependencies" plugins;
  python3Env = pkgs.python3Packages.python.withPackages (ps:
    [ ps.pynvim ]
    ++ (utils.combineFns extraPython3Packages ps)
    ++ (lib.concatMap (f: f ps) pluginPython3Packages));

  luaEnv = neovim.lua.withPackages (utils.combineFns extraLuaPackages);

  wrapperArgs = 
    let
      binPath = lib.makeBinPath (
        lib.optionals withRuby [ rubyEnv ]
        ++ lib.optionals withNodeJs [ pkgs.nodejs ]);
    in 
    [ "--inherit-argv0" ]
    ++ lib.optionals (binPath != "") [ "--suffix" "PATH" ":" "${binPath}" ]
    ++ lib.optionals withRuby [ "--set" "GEM_HOME" "${rubyEnv}/${rubyEnv.ruby.gemPath}" ]
    ++ lib.optionals (luaEnv != null) [
      "--prefix" "LUA_PATH" ";" "${neovim.lua.pkgs.luaLib.genLuaPathAbsStr luaEnv}"
      "--prefix" "LUA_CPATH" ";" "${neovim.lua.pkgs.luaLib.genLuaCPathAbsStr luaEnv}"
    ]
    ++ extraMakeWrapperArgs;

  # We don't create any rc
in
(pkgs.callPackage ./neovimWrapper.nix { }) neovim {
  inherit luaConfig aliases wrapRc wrapperArgs luaEnv extraName;

  inherit withNodeJs;
  inherit withRuby rubyEnv;
  inherit withPerl perlEnv;
  inherit withPython3 python3Env python3WrapperArgs;
}
