return {
    "numToStr/Comment.nvim",
    name = "comment.nvim",
    event = { "BufReadPost", "BufNewFile", "BufWritePre" },
    opts = {
        ignore = "^$",
    },
}
