{ pkgs }:
plugins: 
let
  utils = pkgs.callPackage ./patchUtils.nix{};

  inherit (utils) 
    urlSub githubUrlSub 
    stringSub keyedStringSub 
    optPatch;

  opt = optPatch plugins;
in with pkgs.vimPlugins;
  opt lazy-nvim (stringSub "lazy.nvim-plugin-path" "${lazy-nvim}")
  ++ opt comment-nvim (githubUrlSub "numToStr/Comment.nvim" comment-nvim)
  ++ opt luasnip (githubUrlSub "L3MON4D3/LuaSnip" luasnip)


