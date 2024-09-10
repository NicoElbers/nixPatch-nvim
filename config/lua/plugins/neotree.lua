return {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
        "MunifTanjim/nui.nvim",
        "3rd/image.nvim",
    },
    opts = {
        event_handlers = {
            {
                event = "file_opened",
                handler = function()
                    require("neo-tree.command").execute({ action = "close" })
                end,
            },
        },
    },
    -- config = function(_, opts)
    --     require("neo-tree").setup(opts)
    --     -- vim.keymap.set("n", "<C-n>", ":Neotree filesystem reveal left<cr>")
    -- end,
    keys = {
        { "<C-n>", ":Neotree filesystem reveal left<cr>" },
    },
}
