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
