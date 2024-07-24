{ pkgs, ... }:
let
  # FIXME: Make sure every valid way of specifying a plugin is covered
  # this might take a rewrite of the substitution system and then change the parsing. 
  # IDEA: Give substitutions types. 
  #   -> A type for github URLS which looks for 
  #       url = ${String of {url}} 
  #       ${String of {url}} 
  #       url = ${String of {short_url}} 
  #       ${String of {short_url}} 
  #   -> A type for normal URLs
  #       url = ${String of {url}} 
  #       ${String of {url}} 
  #   -> A type for string replacement
  #       ${String of {given}} 
  #   -> A type for general replacement
  #       {given} 
  # Here ${String of {x}} means `"x"` `'x'` or `[[x]]`
  githubURL = shortUrl: plugin:
    [
      {
        from = ''"${shortUrl}"''; # Be sure to also take the quotes
        to = ''
          dir = [[${plugin}]],
          name = [[${plugin.pname}]]
        '';
      }
      {
        from = ''url = "https://github.com/${shortUrl}"'';
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
