patcher:
{
  # We require nixpkgs because the wrapper parses it later
  nixpkgs
  , system
  , dependencyOverlays
}:
# TODO: Get specialArgs to work
{ configuration, specialArgs ? null, extra_pkg_config ? {}, name ? "nv" }:
let
  utils = import ../utils;

  pkgs = import nixpkgs ({
    inherit system;
    overlays = if builtins.isList dependencyOverlays
        then dependencyOverlays
        else if builtins.isAttrs dependencyOverlays && builtins.hasAttr system dependencyOverlays
        then dependencyOverlays.${system}
        else [];
  } // { config = extra_pkg_config; });
  lib = pkgs.lib;

  rawconfiguration = configuration { inherit pkgs; };

  finalConfiguration = {
    # luaPath cannot be merged
    plugins = [ ];
    aliases = [ ];
    runtimeDeps = [ ];
    environmentVariables = { };
    extraWrapperArgs = [ ];

    python3Packages = [ ];
    extraPython3WrapperArgs = [ ];

    luaPackages = [ ]; # FIXME: why is this not being used????

    propagatedBuildInputs = [ ];
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
  // { wrapRc = true; };

  inherit (finalConfiguration) 
    luaPath plugins runtimeDeps extraConfig
    environmentVariables python3Packages 
    extraPython3WrapperArgs customSubs aliases
    extraWrapperArgs sharedLibraries;

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
    ++
    (
     if builtins.isList extraWrapperArgs then extraWrapperArgs 
     else if builtins.isString then [extraWrapperArgs]
     else throw "extraWrapperArgs should be a string or list of strings"
    );

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

  customSubsPatched = 
    customSubs 
    ++ lib.optionals patchSubs (pkgs.callPackage ./../../subPatches.nix {});

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
(pkgs.callPackage ./neovimWrapper.nix {}) neovim {
    inherit luaConfig;
    inherit wrapRc wrapperArgs;
    inherit aliases;
    inherit name extraName;
    inherit manifestRc;
    inherit packpathDirs;
}
