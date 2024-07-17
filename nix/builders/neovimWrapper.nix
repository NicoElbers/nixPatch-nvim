{
  stdenv
  , lib
  , makeWrapper
  , writeText
  , nodePackages
  , python3
  , callPackage
  , lndir
}:
neovim-unwrapped:
let
  lua = neovim-unwrapped.lua;
  wrapper = {
    luaConfig
    , luaEnv
    , aliases ? null
    , wrapRc ? true
    , wrapperArgs ? ""
    , extraName ? ""
    , withRuby ? false
    , rubyEnv ? null
    , withPython3 ? false
    , python3Env ? null
    , withPerl ? false
    , perlEnv ? null
    , withNodeJs ? false
    , python3WrapperArgs ? ""
  }:
  let
    name = "nv-test";
  in 
  stdenv.mkDerivation (finalAttrs: 
    let
      finalMakeWrapperArgs =
        [ "${neovim-unwrapped}/bin/nvim" "${placeholder "out"}/bin/${name}"]
        ++ lib.optionals finalAttrs.wrapRc [ "--add-flags" "-u ${luaConfig}/init.lua" ];

      extraPython3ArgsStr = builtins.concatStringsSep " " python3WrapperArgs;

      wrapperArgsStr = if lib.isString wrapperArgs then wrapperArgs else lib.escapeShellArgs wrapperArgs;
    in {
      name = "neovim-${lib.getVersion neovim-unwrapped}${extraName}";

      __structuredAttrs = true;
      dontUnpack = true;

      inherit withNodeJs;
      inherit withRuby rubyEnv;
      inherit withPerl perlEnv;
      inherit withPython3 python3Env;
      inherit wrapRc;

      postBuild = lib.optionalString stdenv.isLinux ''
        rm $out/share/applications/nvim.desktop
        substitute ${neovim-unwrapped}/share/applications/nvim.desktop $out/share/applications/${name}.desktop \
              --replace 'Name=Neovim' 'Name=${name}'\
              --replace 'TryExec=nvim' 'TryExec=${name}'\
              --replace 'Exec=nvim %F' 'Exec=${name} %F'
      ''
      + lib.optionalString finalAttrs.withPython3 ''
        makeWrapper ${python3Env.interpreter} $out/bin/${name}-python3 --unset PYTHONPATH ${extraPython3ArgsStr}
      ''
      + lib.optionalString finalAttrs.withRuby ''
        ln -s ${finalAttrs.rubyEnv}/bin/neovim-ruby-host $out/bin/${name}-ruby
      ''
      + lib.optionalString finalAttrs.withNodeJs ''
        ln -s ${nodePackages.neovim}/bin/neovim-node-host $out/bin/${name}-node
      ''
      + lib.optionalString finalAttrs.withPerl ''
        ln -s ${perlEnv}/bin/perl $out/bin/${name}-perl
      ''
      + lib.optionalString (aliases != null)
      (builtins.concatStringsSep "\n" (builtins.map (alias: ''
        ln -s $out/bin/${name} $out/bin/${alias}
      '') aliases))
      + /* bash */ ''
        rm $out/bin/nvim

        source ${lua}/nix-support/utils.sh

        makeWrapper ${lib.escapeShellArgs finalMakeWrapperArgs} ${wrapperArgsStr} \
          --prefix LUA_PATH ';' "$LUA_PATH" \
          --prefix LUA_CPATH ';' "$LUA_CPATH"
      '';

        # makeWrapper ${lib.escapeShellArgs finalMakeWrapperArgs} ${wrapperArgsStr} \
        #   --prefix LUA_PATH ';' "$LUA_PATH" \
        #   --prefix LUA_CPATH ';' "$LUA_CPATH"

      buildPhase = ''
        runHook preBuild

        mkdir -p $out
        for i in ${neovim-unwrapped}; do 
          lndir -silent $i $out
        done
        
        runHook postBuild
      '';

      preferLocalBuild = true;
      nativeBuildInputs = [ makeWrapper lndir ];

      # TODO: potentially add passtru

      meta = neovim-unwrapped.meta // {
        hydraPlatforms = [ ];
        priority = (neovim-unwrapped.meta.priority or 0) -1;
      };
    });
in 
  lib.makeOverridable wrapper
