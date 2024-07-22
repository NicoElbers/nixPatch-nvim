return {
    "numToStr/Comment.nvim",
    -- event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    keys = {
        { "gcc" },
        { "gbc" },
        { "gcO" },
        { "gco" },
        { "gcA" },
        { "gc", mode = "v" },
        { "gb", mode = "v" },
    },

    opts = {
        ignore = "^$",
    },
}
