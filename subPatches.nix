{ pkgs }:
plugins: 
let
  utils = pkgs.callPackage ./patchUtils.nix{};

  # For more information about the different types of subsitutions, go here:
  # https://github.com/NicoElbers/nixPatch-nvim/blob/main/patchUtils.nix
  inherit (utils) 
    urlSub githubUrlSub 
    stringSub keyedStringSub 
    optPatch;

  # This `opt` function optionally enables a subsitution. This way I can put every
  # subsitution I want in here, but they'll only activate if you have the associated 
  # plugin in your list of plugins
  opt = optPatch plugins;
in with pkgs.vimPlugins;
  opt lazy-nvim (stringSub "lazy.nvim-plugin-path" "${lazy-nvim}")
  ++ opt comment-nvim (githubUrlSub "numToStr/Comment.nvim" comment-nvim)
  ++ opt luasnip (githubUrlSub "L3MON4D3/LuaSnip" luasnip)


