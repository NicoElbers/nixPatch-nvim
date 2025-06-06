{
  stdenv
  , lib
  , makeWrapper
  , writeText
  , callPackage
  , lndir
}:
neovim-unwrapped:
let
  lua = neovim-unwrapped.lua;
  wrapper = {
    luaConfig
    , packpathDirs 
    , manifestRc
    , aliases ? null
    , extraName ? ""
    , wrapRc ? true
    , wrapperArgs ? ""
    , name ? "nixPatch"
  }:
  stdenv.mkDerivation (finalAttrs: 
    let
      rtp = (callPackage ./rtpBuilder.nix {}) neovim-unwrapped packpathDirs;

      generatedWrapperArgs = [ "--set" "VIMRUNTIME" "${rtp}/runtime" ];

      finalMakeWrapperArgs =
        [ "${neovim-unwrapped}/bin/nvim" "${placeholder "out"}/bin/${name}"]
        ++ [ "--set" "NVIM_SYSTEM_RPLUGIN_MANIFEST" "${placeholder "out"}/rplugin.vim" ]
        ++ lib.optionals finalAttrs.wrapRc [ "--add-flags" "-u ${luaConfig}/init.lua" ]
        ++ generatedWrapperArgs;

      wrapperArgsStr = if lib.isString wrapperArgs then wrapperArgs else lib.escapeShellArgs wrapperArgs;
    in {
      name = "${name}-${lib.getVersion neovim-unwrapped}${extraName}";

      __structuredAttrs = true;
      dontUnpack = true;

      inherit wrapRc generatedWrapperArgs;

      postBuild = lib.optionalString stdenv.isLinux /*bash*/ ''
        mkdir -p $out/share/applications
        substitute ${neovim-unwrapped}/share/applications/nvim.desktop $out/share/applications/${name}.desktop \
              --replace-fail 'Name=Neovim' 'Name=${name}'\
              --replace-fail 'TryExec=nvim' 'TryExec=${name}'\
              --replace-fail 'Icon=nvim' 'Icon=${neovim-unwrapped}/share/icons/hicolor/128x128/apps/nvim.png' 

      sed -i '/^Exec=nvim/c\Exec=${name} "%F"' $out/share/applications/${name}.desktop

        echo "created desktop file"
      ''
      + lib.optionalString (manifestRc != null) (let
        manifestWrapperArgs = 
          [ "${neovim-unwrapped}/bin/nvim" "${placeholder "out"}/bin/nvim-wrapper" ]
          ++ finalAttrs.generatedWrapperArgs;
      in /*bash*/ ''
        # Copied straight from nixpkgs, not 100% certain what it does
        # but no need to remove it
        echo "Generating remote plugin manifest"
        export NVIM_RPLUGIN_MANIFEST=$out/rplugin.vim
        makeWrapper ${lib.escapeShellArgs manifestWrapperArgs} ${wrapperArgsStr}

        # Some plugins assume that the home directory is accessible for
        # initializing caches, temporary files, etc. Even if the plugin isn't
        # actively used, it may throw an error as soon as Neovim is launched
        # (e.g., inside an autoload script), causing manifest generation to
        # fail. Therefore, let's create a fake home directory before generating
        # the manifest, just to satisfy the needs of these plugins.
        #
        # See https://github.com/Yggdroot/LeaderF/blob/v1.21/autoload/lfMru.vim#L10
        # for an example of this behavior.
        export HOME="$(mktemp -d)"


        # Launch neovim with a vimrc file containing only the generated plugin
        # code. Pass various flags to disable temp file generation
        # (swap/viminfo) and redirect errors to stderr.
        # Only display the log on error since it will contain a few normally
        # irrelevant messages.
        if ! $out/bin/nvim-wrapper \
          -u ${writeText "manifest.vim" manifestRc} \
          -i NONE -n \
          -V1rplugins.log \
          +UpdateRemotePlugins +quit! > outfile 2>&1; then
          cat outfile
          echo -e "\nGenerating rplugin.vim failed!"
          exit 1
        fi
        rm "${placeholder "out"}/bin/nvim-wrapper"

        # Not sure why this touch is here, but I guess it's a good failsafe
        # in case the previous code doesn't work for whatever reason
        touch $out/rplugin.vim
      '')
      + /* bash */ ''

        echo "Looking for lua dependencies..."

        # Ignore failures here, since older nix versions didn't have these
        # functions
        source ${lua}/nix-support/utils.sh || true
        _addToLuaPath "${rtp}" || true
        
        echo "LUA_PATH: $LUA_PATH"
        echo "LUA_CPATH: $LUA_CPATH"

        makeWrapper ${lib.escapeShellArgs finalMakeWrapperArgs} ${wrapperArgsStr} \
          --prefix LUA_PATH ';' "$LUA_PATH" \
          --prefix LUA_CPATH ';' "$LUA_CPATH"
      ''
      # Finally, symlink some aliases
      + lib.optionalString (aliases != null)
      (builtins.concatStringsSep "\n" (builtins.map (alias: /*bash*/ ''
        ln -s $out/bin/${name} $out/bin/${alias}
      '') aliases));

      preferLocalBuild = true;
      nativeBuildInputs = [ makeWrapper lndir ];

      passthru = {
          finalPackDir = rtp;

          unwrapped = neovim-unwrapped;
          config = luaConfig;
      };

      meta = neovim-unwrapped.meta // {
        hydraPlatforms = [ ];
        priority = (neovim-unwrapped.meta.priority or 0) -1;
      };
    });
in 
  lib.makeOverridable wrapper
