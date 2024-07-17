return {
    "mbbill/undotree",
    -- lazy = false,
    opt = {},
    keys = {
        {
            "<leader>u",
            function()
                vim.cmd.UndotreeToggle()
                vim.cmd.UndotreeFocus()
            end,
        },
    },
}
