local utils = require("utils")

return {
    {
        "iamcco/markdown-preview.nvim",
        cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
        ft = { "markdown" },
        build = utils.set(function()
            vim.fn["mkdp#util#install"]()
        end),
    },
}
