return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.5",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "debugloop/telescope-undo.nvim",
            "nvim-telescope/telescope-ui-select.nvim",
        },
        config = function()
            vim.defer_fn(function()
                local conf = require("telescope")
                conf.setup({
                    extensions = {
                        ["ui-select"] = {
                            require("telescope.themes").get_dropdown({}),
                        },
                        undo = {},
                    },
                })

                conf.load_extension("ui-select")
                conf.load_extension("undo")

                local builtin = require("telescope.builtin")
                vim.keymap.set("n", "<leader>pf", builtin.find_files)
                vim.keymap.set("n", "<leader>ps", builtin.live_grep)
                vim.keymap.set("n", "<leader>?", builtin.oldfiles)
                vim.keymap.set("n", "<leader>u", "<cmd>Telescope undo<cr>")

                vim.keymap.set("n", "gr", builtin.lsp_references)
            end, 0)
        end,
    },
}
