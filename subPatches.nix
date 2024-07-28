{ pkgs, ... }:
let
  githubURL = shortUrl: plugin:
    [
      {
        type = "plugin";
        from = "${shortUrl}";
        to = "${plugin}";
        extra = "${plugin.pname}";
      }
      {
        type = "plugin";
        from = ''https://github.com/${shortUrl}'';
        to = "${plugin}";
        extra = "${plugin.pname}";
      }
    ];
in with pkgs.vimPlugins; [
  {
    type = "string";
    from = "lazy.nvim-plugin-path";
    to = "${lazy-nvim}";
    extra = null;
  }
] 
++ (githubURL "numToStr/Comment.nvim" comment-nvim)
++ (githubURL "L3MON4D3/LuaSnip" luasnip)
# FIXME: Also parse overrides.nix
# https://github.com/NixOS/nixpkgs/commit/c9b408ea5d6277213462690eee46ae1ab1b03a92
++ (githubURL "mrcjkb/rustaceanvim" rustaceanvim)
