# nv: keep your lazy.nvim config in lua

<!--toc:start-->

- [nv: keep your lazy.nvim config in lua](#nv-keep-your-lazynvim-config-in-lua)
  - [Goals](#goals)
  - [Limitations](#limitations)
  - [Roadmap](#roadmap)
  <!--toc:end-->

`nv` is a wrapper around Neovim that makes your lua configuration nix compatible. It makes the barrier to a working Neovim configuration on nix as small as possible for existing Neovim users.

As the creator of [nixCats](https://github.com/BirdeeHub/nixCats-nvim) aptly said, nix is for downloading and lua is for configuring. I am taking that idea further to having to change as little as possible to your existing configuration and getting all the benefits nix offers.

`nv` provides a flake template that you can put inside your Neovim configuration. You have to make a couple minor adjustments to your configuration and specify what dependencies your configuration has and `nv` will do the rest.

## Why

Primarily, for fun. Besides that because I have a use case that wasn't properly fulfilled by the alternatives I saw. I have a Neovim configuration I am very happy with. I don't want to convert it to nix like nixvim suggests and I also don't have the need for multiple configurations like nixCats offeres.

## Installation

### Setting up your config

`nv` does it's best to work with existing lazy.nvim configurations, but it's not perfect. The setup you need to however, is minimal. There are 3 main limitations as of now:

1. Plugin dependencies must be wrapped in brackets `{}` to be correctly parsed.
2. Plugins that install files, like mason, don't play nice with nix.
3. lazy.nvim isn't loaded by lazy.nvim, so we need a special way to be able to load it correctly.

#### Setting up dependencies

Setting up dependencies is mainly an annoyance and planned to not be needed in the future. The easiest way to do it is to go through every file where you install plugins and see if they have dependencies. If they do, and they are not already wrapped in brackets, highlight them `Shift-v`, then do the following search and replace: `:'<,'>s/\v(\s*)(.*)/\1{\r\1\t\2\r\1},`. This might look very intimidating, but it's not that difficult. Here's what it does:

- `:'<,'>` This is what appears by default when you enter a command while having some text selected. It will perform your command on that range
- `s/` This starts a search (and replace)
- `\v` This enables "very magic" mode, which means we have to escape less characters
- `(\s*)` This will select 0 or more whitespace characters, and capture them in group 1
- `(.*)` This will select 0 or more characters, until the end of the line and capture them in group 2
- `/` "we want to replace with everything after this"
- `\1{\r` First put capture group 1 here (all the whitespace), then a `{` and then a newline `\r`
- `\1\t\2\r` Put the first capture group here, then a tab, then the second capture group, and finally a newline
- `\1},` Put whitespace, `}` and finally a comma

Ok I admit, this is a little complicated, but it's things like this that make Neovim fun! If you want more information about all this, I highly recommend [this website](https://learnvim.irian.to/basics/search_and_substitute) or look through the vim docs using `:help`!

**TLDR**; turn this:

```lua
dependencies = {
  "Some/plugin",
  "other/plugin",
},
```

into this:

```lua
dependencies = {
  {
    "Some/plugin",
  },
  {
    "other/plugin",
  },
},

```

#### Utilities

For the other 2 limitations you do need to make some changes to your configuration, luckily you still don't have to change a thing when you're not on nix!

The trick to this is very simple. `nv` does very little magic, but the one bit of magic it does set the global `vim.g.nixos` to `true`. This allows us to make a very useful utility function:

```lua
local set = function(nonNix, nix)
    if vim.g.nixos == true then
        return nix
    else
        return nonNix
    end
end
```

Function inspired by [nixCats](https://github.com/BirdeeHub/nixCats-nvim), thank you BirdeeHub!

We can give a nonNix and a nix value to this function, but what exactly does that do? It means we can assign values, or functions, or anything really based on if we're using nix or not. So for example on nix we can disable mason, or we can have different setup functions on nix and non nix.

<details><summary>How to better integrate the function</summary>

Of course, it's not very nice to have to copy this function over everywhere, for that I personally have a `lua/utils.lua` file. This file roughly looks like this:

```lua
-- Set M to an empty table
local M = {}

-- snip

-- Add boolean values to this table
M.isNix = vim.g.nixos == true
M.isNotNix = vim.g.nixos == nil

-- Add the set function to this table,
-- we can now call it with require("utils").set(a, b)
function M.set(nonNix, nix)
    if M.isNix then
        return nix
    else
        return nonNix
    end
end

-- snip

return M
```

That way I can call `require("utils")` anywhere in my config and have access to `set`! For an example, see [my config](https://github.com/NicoElbers/nvim-config/blob/ed31459b8611da8b91f2979b825e03d8eb553f3f/init.lua#L6-L24).

</details>

#### Loading lazy.nvim

On nonNix [the lazy docs](https://lazy.folke.io/installation) tell you to add this to your config:

```lua
-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)
```

This is downloading something imperatively, which we want to avoid on nix. Luckily this is super easy to change with our utility. The problem is what do we replace it with?

This is another piece of sort of magic `nv` does. The lua string `"lazy.nvim-plugin-path"` is replaced with the appropriate path to the lazy.nvim plugin. This works because `nv` provides some default patches if they otherwise wouldn't work out of the box, among these I added the string `"lazy.nvim-plugin-path"` to be replaced. You can see all default patches in the [`subPatches.nix`](https://github.com/NicoElbers/nv/blob/main/subPatches.nix) file. You can also add your own, as you'll see a bit later.

**Beware** if you turn off the `patchSubs` setting, this will no longer work.

Here is how that looks in practice:

```lua
local set = function(nonNix, nix)
    if vim.g.nixos == true then
        return nix
    else
        return nonNix
    end
end

-- Bootstrap lazy.nvim
local load_lazy = set(function()
  local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
  if not (vim.uv or vim.loop).fs_stat(lazypath) then
    local lazyrepo = "https://github.com/folke/lazy.nvim.git"
    local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
        { out, "WarningMsg" },
        { "\nPress any key to exit..." },
      }, true, {})
      vim.fn.getchar()
      os.exit(1)
    end
  end
  vim.opt.rtp:prepend(lazypath)
end, function()
    -- Prepend the runtime path with the directory of lazy
    -- This means we can call `require("lazy")`
    vim.opt.rtp:prepend([[lazy.nvim-plugin-path]])
end)

-- Actually execute the loading function we set above
load_lazy()
```

#### Dealing with mason and the like

<!-- TODO: make -->

Now that we already have our utility functions this is pretty easy. I'll give my own examples here in the future, for now look at how nixCats does it. If you replace `require('nixCatsUtils).lazyadd` with our `set` function, everything works the same.

- [Downloading the mason plugins](https://github.com/BirdeeHub/nixCats-nvim/blob/f917800c75ae42bfec3014ea6b79252d6cc23546/nix/templates/kickstart-nvim/init.lua#L487-L509)
- [Using mason for lsp configuration](https://github.com/BirdeeHub/nixCats-nvim/blob/f917800c75ae42bfec3014ea6b79252d6cc23546/nix/templates/kickstart-nvim/init.lua#L702-L748)

### Getting the flake

<!-- TODO: finish -->

Inside the directory where you have your configuration do `nix flake init -t github:NicoElbers/nv`. This creates a `flake.nix`. Inside this flake you will find the outlines for everything you need.

### Setting up the flake

<!-- TODO: make -->

## Goals

1. Make any lazy.nvim configuration nix compatible
2. Keep Neovim fast
3. Easy setup for anyone

## Limitations

Currently `nv` only works for [lazy.nvim](https://github.com/folke/lazy.nvim) configurations. I might add support for plug in the future, however this is not a priority for the project.

<!-- TODO: Verify -->

You might experience issues with aliasing `nv` to `nvim` if you also have Neovim installed and on your path. Therefore it is not aliased by default.

You might experience issues if you use [page](https://github.com/I60R/page) as it also provides a binary named `nv`.

## Roadmap

- [ ] Make the lua parser smarter such that one line plugin url's no longer need to be wrapped
- [ ] Provide a way to iterate over your configuration quickly
  - This would mean that the underlying config patcher be exposed as a program for you to run, updating your settings but not adding new plugins
- [ ] Add support for different package managers
  - This should be pretty simple, however I only use lazy.nvim so it's not a priority for me
- [ ] Provide a script that parses your config and makes the `flake.nix` for you, with plugins and all
- [ ] Make a nixos module / home manager module
  - In my opinion this has friction with the goal of simplicity, as it detaches the Neovim configuration from the nv configuration. Unsure for now.
