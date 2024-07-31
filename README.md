# nv: keep your lazy.nvim config in lua

<!--toc:start-->

- [nv: keep your lazy.nvim config in lua](#nv-keep-your-lazynvim-config-in-lua)
  - [Why](#why)
  - [Installation](#installation)
    - [Setting up your config](#setting-up-your-config)
      - [Setting up dependencies](#setting-up-dependencies)
      - [Utilities](#utilities)
      - [Loading lazy.nvim](#loading-lazynvim)
      - [Dealing with mason and the like](#dealing-with-mason-and-the-like)
    - [Setting up the nix part](#setting-up-the-nix-part)
  - [Goals](#goals)
  - [Limitations](#limitations)
  - [Roadmap](#roadmap)
  - [How it works](#how-it-works)
  - [Blocks for release](#blocks-for-release)
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

The trick to this is very simple. `nv` does very little magic, but the one bit of magic it does set the global `vim.g.nix` to `true`. This allows us to make a very useful utility function:

```lua
local set = function(nonNix, nix)
    if vim.g.nix == true then
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
M.isNix = vim.g.nix == true
M.isNotNix = vim.g.nix == nil

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
    if vim.g.nix == true then
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

### Setting up the nix part

Inside the directory where you have your configuration do `nix flake init -t github:NicoElbers/nv`. This creates a `flake.nix`. Inside this flake you will find the outlines for everything you need.

The main things you need to look out for are `plugins`, `runtimeDeps` and `luaPath`.

- luaPath: This is very simply the path to your configuration root, aka the directory which contains your `init.lua`
- plugins: This is where you tell nix what plugins to download. This will take a little bit of time, the easiest way I have found to do this is to put 'vimPlugins' in [nixos search](https://search.nixos.org/packages?channel=unstable&from=-1&size=50&sort=relevance&type=packages&query=vimPlugins) and search for all your plugins there. In my experience, with a little bit of fiddling, this worked best. After that, do `nix build`, and try to execute `./result/bin/nv`. Once everything is loaded you can do `:Lazy`, where you see all yourplugins. Every dot that is blue means that the plugin was downloaded from github aka you need to add that plugin to your list. Once everything is done all the dots should be orange. Should you have installed everything but lazy is still downloading something, look at the "Custom patches" tab below.
- runtimeDeps: This is all the external executables neovim will have access to. This is things like `tree-sitter` and your lsp's. Same here, look at [nixos search](https://search.nixos.org/packages?channel=unstable) and look for the executable. In my experience some lsp's have weird names so you might need to search a little. Feel free to use [my config](https://github.com/NicoElbers/nvim-config/blob/4e686f8fc2a2e0dd980998f4497005849bdb314d/flake.nix#L168-L207) as a starting point.

The other options are hopefully explained well enough in the template. If not, feel free to make an issue and or pr.

If you want to see what your config looks like, to find errors or just for fun, `vim.g.configpath` contains the location your patched config is currently located.

<details><summary>Custom patches</summary>

nv provides you with the possibility to define custom subsitutions (look at [how it works](#how-it-works) for more details). These can be used to change any lua string into any other lua string. A specialization of these are plugin subsitutions. These assume that whatever you're replacing is a url and will replace a bit of fluff around it to satisfy lazy.nvim.

In most cases you're gonna want to use a plugin subsitution. You can generate these very easily WHEN I EXPOSE THE FUCKING FUNCTIONS IT'S NOT THAT MUCH WORK JUST DO IT. When you have them generated, you need to put them in `customSubs` in your flake. After this you should be good.

In the cases that you want to use literal string replacement, a couple of things to note:

- You can only replace lua strings (wrapped in `''`, `""` or `[[]]`), you can't change arbitrary characters.
- Be careful what strings you're replacing. _Every_ lua string in your _entire_ config will be checked. Notably, this includes inside comments
- The string you're replacing is matched fully. No substring matching, _every character has to match exactly_.
- You cannot put code in your configuration. Everything you replace will be wrapped by `[[]]`, lua's multiline string. String replacment is only meant to pass values from nix to your configuration. If you want specific code to run when you're using nix, use the `set` function discussed above.
- You _can_ escape the multiline string if you really want, I don't validate your input in any way, but I make 0 guarantees it'll work in the future.

</details>

## Goals

1. Make any lazy.nvim configuration nix compatible
2. Keep Neovim fast
3. Easy setup for anyone

## Limitations

- Currently `nv` only works for [lazy.nvim](https://github.com/folke/lazy.nvim) configurations. I might add support for plug in the future, however this is not a priority for the project.
- You might experience issues with aliasing `nv` to `nvim` if you also have Neovim installed and on your path. Therefore it is not aliased by default.
- You might experience issues if you use [page](https://github.com/I60R/page) as it also provides a binary named `nv`.

## Roadmap

- [ ] Make the lua parser smarter such that one line dependency plugin url's no longer need to be wrapped
- [ ] Provide a way to iterate over your configuration quickly
  - This would mean that the underlying config patcher be exposed as a program for you to run, updating your settings but not adding new plugins
- [ ] Add support for different package managers
  - This should be pretty simple, however I only use lazy.nvim so it's not a priority for me
- [ ] Provide a script that parses your config and makes the `flake.nix` for you, with plugins and all
- [ ] Make a nixos module / home manager module
  - In my opinion this has friction with the goal of simplicity, as it detaches the Neovim configuration from the nv configuration. Unsure for now.

## How it works

## Blocks for release

- [ ] The provided subPatches force you to download plugins. It should be optional depending on if the plugin is in your plugin list.
- [ ] Exposing the subPatches functions to the user
- [ ] A quicksetup section
- [ ] Expanding in the [opening section](#nv-keep-your-lazy.nvim-config-in-lua)
- [ ] Expanding in [why](#why)
- [ ] Expand on [goals](#goals)
- [ ] Expose the config path in `vim.g.configpath`
