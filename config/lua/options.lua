-- Leader key
vim.g.mapleader = " "

-- Very useful options
-- clipboard
vim.opt.clipboard = "unnamedplus"

-- Line numbers
vim.opt.rnu = true
vim.opt.nu = true
vim.opt.scrolloff = 15

-- Tabs
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4

-- Wrap
vim.opt.wrap = false
vim.opt.breakindent = true

-- Undo files
vim.opt.undofile = true

-- Searching
vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Update time
vim.opt.updatetime = 100
vim.opt.timeout = true
vim.opt.timeoutlen = 300

-- Cool colors
vim.opt.cursorline = true
vim.opt.colorcolumn = { 80, 81 }

-- Required for formatting I think, can't be fucked to check
-- vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

-- Set whitespace characters
vim.opt.listchars:append({
    multispace = "·",
    lead = "·",
    trail = "·",
    nbsp = "·",
    eol = "↵",
})
vim.opt.list = true

-- local colorschemeName = "catppuccin-mocha"
-- vim.cmd.colorscheme(colorschemeName)
