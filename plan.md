# Main idea

lazy.nvim allows for github links and directories.

- In your lua config you will have github links to plugins.
- In your nix config you will have a list of installed plugins.
- In nixpkgs, you have the "homepage" link, to the github.

We can assume that if you use a plugin that is not a github link, it's stored
somewhere locally so we don't care about it.

Now, we can look at your list of plugins and your provided nixpkgs. Scrape the
github links for the relevant plugins. And then while moving your config to the
store, replace the github links with the store links!

## Zig input

Zig input will be:

1. path to nixpkgs source
2. outpath for config
3. a string mixing plugin names (pname) with the associated version and path
   in the manner `pname|version|path;pname|version|path;...`
4. All other arguments are considered lua configuration to be put at the front of
   `init.lua`

The program also assumes that the directory it's being ran in is the directory
containing all the neovim config.
