# Effectively copied and minimized from
# https://github.com/BirdeeHub/nixCats-nvim/blob/77f400d39ad26023f818de365a078d6d532a2c56/nix/builder/vim-pack-dir.nix
{
  lib
  , stdenv
  , buildEnv
  , writeText
  , runCommand
  , python3
  , linkFarm
}:
neovim-unwrapped:
let
  depFinderClosure = plugin:
    [plugin] ++ (lib.unique (builtins.concatLists (map depFinderClosure plugin.dependencies or [])));

  recursiveDepFinder = plugins: lib.concatMap depFinderClosure plugins;

  vimFarm = prefix: name: drvs:
    linkFarm name (map (drv: { name = "${prefix}/${lib.getName drv}"; path = drv; }) drvs);

  # apparently this is ACTUALLY the standard. Yeah. Strings XD
  # If its stable enough for nixpkgs I guess I can use it here.
  grammarMatcher = entry: 
    (if entry != null && entry.name != null then 
      (if (builtins.match "^vimplugin-treesitter-grammar-.*" entry.name) != null
      then true else false)
    else false);

  mkEntryFromDrv = drv: { name = "${lib.getName drv}"; value = drv; };

# TODO: Go through all this and simplify
# - I know that I can remove the start, opt things, and change it to just a list
#   of plugins. I only use one regardless.
# - I might be able to put any of our plugins in the rtp, that way I think a 
#   lazy warning will go away
packDir = packages:
  let
  packageLinks = packageName: {start ? [], opt ? []}:
    let
      depsOfOptionalPlugins = lib.subtractLists opt (recursiveDepFinder opt);
      startWithDeps = recursiveDepFinder start;
      allPlugins = lib.unique (startWithDeps ++ depsOfOptionalPlugins);

      allPluginsMapped = (map mkEntryFromDrv allPlugins);

      startPlugins = builtins.listToAttrs
        (builtins.filter (entry: ! (grammarMatcher entry)) allPluginsMapped);

      allPython3Dependencies = ps:
        lib.flatten (builtins.map (plugin: (plugin.python3Dependencies or (_: [])) ps) allPlugins);
      python3Env = python3.withPackages allPython3Dependencies;

      ts_grammar_plugin = with builtins; stdenv.mkDerivation (let 
        treesitter_grammars = (map (entry: entry.value)
          (filter (entry: grammarMatcher entry) allPluginsMapped));

        builderLines = map (grmr: /* bash */''
          cp --no-dereference ${grmr}/parser/*.so $out/parser
        '') treesitter_grammars;

        builderText = /* bash */''
          #!/usr/bin/env bash
          source $stdenv/setup
          mkdir -p $out/parser
        '' + (concatStringsSep "\n" builderLines);

      in {
        name = "vimplugin-treesitter-grammar-ALL-INCLUDED";
        builder = writeText "builder.sh" builderText;
      });

      packdirStart = vimFarm "pack/${packageName}/start" "packdir-start"
            ( (builtins.attrValues startPlugins) ++ [ts_grammar_plugin]);

      packdirOpt = vimFarm "pack/${packageName}/opt" "packdir-opt" opt;

      # Assemble all python3 dependencies into a single `site-packages` to avoid doing recursive dependency collection
      # for each plugin.
      # This directory is only for python import search path, and will not slow down the startup time.
      # see :help python3-directory for more details
      python3link = runCommand "vim-python3-deps" {} ''
        mkdir -p $out/pack/${packageName}/start/__python3_dependencies
        ln -s ${python3Env}/${python3Env.sitePackages} $out/pack/${packageName}/start/__python3_dependencies/python3
      '';
    in
      [ (neovim-unwrapped + "/share/nvim/runtime") packdirStart packdirOpt ] 
      ++ lib.optional (allPython3Dependencies python3.pkgs != []) python3link;
  in
  buildEnv {
    # TODO: Use a name variable here
    name = "nv-rtp";
    paths = (lib.flatten (lib.mapAttrsToList packageLinks packages));
    # gather all propagated build inputs from packDir
    postBuild = ''
      echo "rtp: $out"

      mkdir $out/nix-support
      for i in $(find -L $out -name propagated-build-inputs ); do
        cat "$i" >> $out/nix-support/propagated-build-inputs
      done
    '';
  };
in packDir
