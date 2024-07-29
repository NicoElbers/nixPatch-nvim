# nv: keep your lazy.nvim config in lua

<!--toc:start-->

- [nv: keep your lazy.nvim config in lua](#nv-keep-your-lazynvim-config-in-lua)
  - [Goals](#goals)
  - [Limitations](#limitations)
  - [Roadmap](#roadmap)
  <!--toc:end-->

`nv` is a wrapper around neovim that makes your lua configuration nix compatible. It makes the barrier to a working neovim configuration on nix as small as possible for existing neovim users.

As the creator of [nixCats](https://github.com/BirdeeHub/nixCats-nvim) aptly said, nix is for downloading and lua is for configuring. I am taking that idea further to having to change as little as possible to your existing configuration and getting all the benefits nix offers.

`nv` provides a flake template that you can put inside your neovim configuration. You have to make a couple minor adjustments to your configuration and specify what dependencies your configuration has and `nv` will do the rest.

## Why

Primarily, for fun. Besides that because I have a use case that wasn't properly fulfilled by the alternatives I saw. I have a neovim configuration I am very happy with. I don't want to convert it to nix like nixvim suggests and I also don't have the need for multiple configurations like nixCats offeres.

## Installation

TODO: If you want an example look [here](https://github.com/NicoElbers/nvim-config). It comes down to wrapping urls under `dependencies` with `{ }`

ex:

```lua
return {
  "owner/some-plugin",
  dependencies = {
    "owner/other-plugin",
  },
}
```

becomes:

```lua
return {
  "owner/some-plugin",
  dependencies = {
    {
    "owner/other-plugin",
    },
  },
}
```

## Goals

1. Make any lazy.nvim configuration nix compatible
2. Keep neovim fast
3. Easy setup for anyone

## Limitations

Currently `nv` only works for [lazy.nvim](https://github.com/folke/lazy.nvim) configurations. I might add support for plug in the future, however this is not a priority for the project.

<!-- TODO: Verify -->

You might experience issues with aliasing `nv` to `nvim` if you also have neovim installed and on your path. Therefore it is not aliased by default.

You might experience issues if you use [page](https://github.com/I60R/page) as it also provides a binary named `nv`.

## Roadmap

- [ ] Make the lua parser smarter such that one line plugin url's no longer need to be wrapped
- [ ] Provide a way to iterate over your configuration quickly
  - This would mean that the underlying config patcher be exposed as a program for you to run, updating your settings but not adding new plugins
- [ ] Add support for different package managers
  - This should be pretty simple, however I only use lazy.nvim so it's not a priority for me
- [ ] Provide a script that parses your config and makes the `flake.nix` for you, with plugins and all
- [ ] Make a nixos module / home manager module
  - In my opinion this has friction with the goal of simplicity, as it detaches the neovim configuration from the nv configuration. Unsure for now.
