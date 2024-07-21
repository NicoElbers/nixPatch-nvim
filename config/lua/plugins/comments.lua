return {
    "numToStr/Comment.nvim",
    event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    opts = {
        ignore = "^$",
    },
}
