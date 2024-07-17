return {
    {
        "iamcco/markdown-preview.nvim",
        cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
        ft = { "markdown" },
        build = require("nixCatsUtils.lazyCat").lazyAdd(function()
            vim.fn["mkdp#util#install"]()
        end),
    },
}
