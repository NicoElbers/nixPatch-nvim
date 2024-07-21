{ pkgs, ... }:
let
  githubURL = shortUrl: plugin:
    [
      {
        from = shortUrl;
        to = ''
          dir = [[${plugin}]],
          name = [[${plugin.pname}]]
        '';
      }
      {
        from = "https://github.com/${shortUrl}";
        to = ''
          dir = [[${plugin}]],
          name = [[${plugin.pname}]]
        '';
      }
    ];
in with pkgs.vimPlugins; [
  {
    from = "vim.opt.rtp:prepend([[lazypath]])";
    to = "vim.opt.rtp:prepend([[${lazy-nvim}]])";
  }
] 
++ (githubURL "numToStr/Comment.nvim" comment-nvim)
++ (githubURL "L3MON4D3/LuaSnip" luasnip)
