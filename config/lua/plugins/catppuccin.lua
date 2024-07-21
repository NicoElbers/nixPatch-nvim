return {
    "catppuccin/nvim",
    priority = 1000,
    config = function()
        -- colorscheme catppuccin " catppuccin-latte, catppuccin-frappe, catppuccin-macchiato, catppuccin-mocha
        vim.cmd.colorscheme("catppuccin-mocha")
    end,
}
