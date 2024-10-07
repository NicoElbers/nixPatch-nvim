patcher:
{
  # We require nixpkgs because the wrapper parses it later
  nixpkgs
  , system
  , dependencyOverlays
}:
# TODO: When we name change, probably best to make name a required argument
# and maybe give an option to do name-override
{ configuration, specialArgs ? null, extra_pkg_config ? {}, name ? "nv" }:
let
  utils = import ../utils;

  # Create packages with your specified overlays
  pkgs = import nixpkgs ({
    inherit system;
    overlays = if builtins.isList dependencyOverlays
        then dependencyOverlays
        else if builtins.isAttrs dependencyOverlays && builtins.hasAttr system dependencyOverlays
        then dependencyOverlays.${system}
        else [];
  } // { config = extra_pkg_config; });
  lib = pkgs.lib;

  # Extract your configuration
  rawconfiguration = configuration { inherit pkgs system specialArgs; };

  finalConfiguration = {
    # luaPath cannot be merged
    plugins = [ ];
    aliases = [ ];
    runtimeDeps = [ ];
    environmentVariables = { };
    extraWrapperArgs = [ ];

    python3Packages = [ ];
    extraPython3WrapperArgs = [ ];

    luaPackages = [ ];

    sharedLibraries = [ ];

    extraConfig = [ ];
    customSubs = [ ];
  } 
  // rawconfiguration;

  finalSettings = {
    withNodeJs = false;
    withRuby = false;
    withPerl = false;
    withPython3 = false;
    extraName = "";
    configDirName = "nvim";
    neovim-unwrapped = null;
    patchSubs = true;
    suffix-path = false;
    suffix-LD = false;
  }
  // rawconfiguration.settings
  # TODO: Make wrapRc optional by adding an option to put
  # config in xdg.config
  #
  # Maybe it's a better idea to not have wrapRc at all, and just give an option
  # to do the quick patch thing automatically putting your config in /tmp. 
  # Since nv patches your config, it should _always_ be wrapped.
  // { wrapRc = true; };

  inherit (finalConfiguration) 
    luaPath plugins runtimeDeps extraConfig
    environmentVariables python3Packages 
    extraPython3WrapperArgs customSubs aliases
    extraWrapperArgs sharedLibraries luaPackages;

  inherit (finalSettings)
    withNodeJs withRuby withPerl withPython3
    extraName configDirName neovim-unwrapped 
    suffix-path patchSubs suffix-LD wrapRc;

  neovim = if neovim-unwrapped == null then pkgs.neovim-unwrapped else neovim-unwrapped;

  # Setup environments
  appendPathPos = if suffix-path then "suffix" else "prefix";
  appendLinkPos = if suffix-LD then "suffix" else "prefix";

  getEnv = env:  lib.flatten 
    (lib.mapAttrsToList (n: v: [ "--set" "${n}" "${v}" ]) env);
 
  mappedPlugins = map (p: { plugin = p; optional = true; }) plugins;

  packpathDirs.packages = 
      let
      part = lib.partition (x: x.optional == true) mappedPlugins;
      in 
      {
        start = map (x: x.plugin) part.wrong;
        opt = map (x: x.plugin) part.right;
      };

  getDeps = attrname: map (plugin: plugin.${attrname} or (_: [ ]));

  # Evn implementations from 
  # https://github.com/NixOS/nixpkgs/blob/748db8ec5cbae3c0bddf63845dc4de51ec6a68d9/pkgs/applications/editors/neovim/utils.nix#L26-L122
  extraPython3PackagesCombined = utils.combineFns python3Packages;
  pluginPython3Packages = getDeps "python3Dependencies" plugins;
  python3Env = pkgs.python3Packages.python.withPackages (ps:
    [ ps.pynvim ]
    ++ (extraPython3PackagesCombined ps)
    ++ (lib.concatMap (f: f ps) pluginPython3Packages));

  rubyEnv = pkgs.bundlerEnv {
    name = "neovim-ruby-env";
    gemdir = ./ruby_provider;
    postBuild = ''
      ln -sf ${pkgs.ruby}/bin/* $out/bin
    '';
  };

  perlEnv = pkgs.perl.withPackages (p: [ p.NeovimExt p.Appcpanminus ]);

  luaEnv = neovim.lua.withPackages (utils.combineFns luaPackages);

  wrapperArgs = 
    let
      binPath = lib.makeBinPath (runtimeDeps
        ++ lib.optionals withNodeJs 
        [ pkgs.nodejs ]
        ++ lib.optionals withRuby
        [ pkgs.ruby ]
        ++ lib.optionals withPython3
        [ pkgs.python3 ]);
        
    in 
    getEnv environmentVariables
    ++
    lib.optionals (configDirName != null && configDirName != "nvim")
    [ "--set" "NVIM_APPNAME" "${configDirName}" ]
    ++ lib.optionals (runtimeDeps != [])
    [ "--${appendPathPos}" "PATH" ":" "${binPath}" ]
    ++ lib.optionals (sharedLibraries != [])
    [ "--${appendLinkPos}" "PATH" ":" "${lib.makeBinPath sharedLibraries}" ]
    ++ lib.optionals (luaEnv != null) 
    [
      "--prefix" "LUA_PATH" ";" (neovim.lua.pkgs.luaLib.genLuaPathAbsStr luaEnv)
      "--prefix" "LUA_CPATH" ";" (neovim.lua.pkgs.luaLib.genLuaCPathAbsStr luaEnv)
    ]
    ++
    (
     # TODO: Do more type safety like this, type safety my beloved
     if builtins.isList extraWrapperArgs then extraWrapperArgs 
     else if builtins.isString then [extraWrapperArgs]
     else throw "extraWrapperArgs should be a string or list of strings"
    );

  # Get the patched lua config
  customSubsPatched = 
    customSubs 
    ++ lib.optionals patchSubs ((pkgs.callPackage ./../../subPatches.nix {}) plugins);

  luaConfig = patcher {
    inherit luaPath plugins name;
    inherit extraConfig;

    customSubs = customSubsPatched;

    inherit withNodeJs;
    inherit withRuby rubyEnv;
    inherit withPerl perlEnv;
    inherit withPython3 python3Env extraPython3WrapperArgs ;
  };

  # Copied from 
  # https://github.com/NixOS/nixpkgs/blob/3178439a4e764da70ca83f47bc144a2a276b2f0b/pkgs/applications/editors/vim/plugins/vim-utils.nix#L227-L277
  manifestRc = ''
      set nocompatible
  '';
in
# Do the now actually put everything together
(pkgs.callPackage ./neovimWrapper.nix {}) neovim {
    inherit luaConfig;
    inherit wrapRc wrapperArgs;
    inherit aliases;
    inherit name extraName;
    inherit manifestRc;
    inherit packpathDirs;
}
