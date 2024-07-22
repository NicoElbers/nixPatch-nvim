-- Load the things
require("options")
require("keymaps")
require("autocmds")

local utils = require("utils")

local load_lazy = utils.set(function()
    local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
    if not vim.loop.fs_stat(lazypath) then
        vim.fn.system({
            "git",
            "clone",
            "--filter=blob:none",
            "https://github.com/folke/lazy.nvim.git",
            "--branch=stable", -- latest stable release
            lazypath,
        })
    end
    vim.opt.rtp:prepend(lazypath)
end, function()
    -- Short URL will be replaced
    vim.opt.rtp:prepend([[lazypath]])
end)

load_lazy()

require("lazy").setup("plugins")
