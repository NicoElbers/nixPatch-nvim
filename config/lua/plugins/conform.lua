return {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    opts = {
        format_on_save = {
            timeout_ms = 500,
            lsp_fallback = true,
        },
        formatters_by_ft = {
            lua = { "stylua" },
            markdown = { "prettierd" },
            rust = { "rustfmt" },
        },
        formatters = {
            prettierd = {},
        },
    },
}
