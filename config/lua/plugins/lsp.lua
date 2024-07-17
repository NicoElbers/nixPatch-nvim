local utils = require("utils")

return {
    {
        "neovim/nvim-lspconfig",
        dependencies = {
            {
                "folke/neodev.nvim",
                opts = {},
            },
            {
                "j-hui/fidget.nvim",
                opts = {},
            },
        },
        ft = {
            "c",
            "c++",
            "lua",
            "markdown",
            "nix",
            "python",
            "html",
            "css",
            "js",
            "ts",
            "zig",
        },
        config = function()
            local capabilities = vim.lsp.protocol.make_client_capabilities()
            capabilities = require("cmp_nvim_lsp").default_capabilities(capabilities)
            capabilities.document_formatting = false

            local lspconfig = require("lspconfig")

            -- c/ c++
            lspconfig.clangd.setup({
                on_attach = utils.on_attach,
                cmd = { "clangd" },
                capabilities = capabilities,
            })

            -- Lua
            lspconfig.lua_ls.setup({
                on_attach = utils.on_attach,
                cmd = { "lua-language-server" },
                capabilities = capabilities,
            })

            -- Markdown
            lspconfig.marksman.setup({
                on_attach = utils.on_attach,
                cmd = { "marksman" },
                capabilities = capabilities,
            })

            -- Nix
            lspconfig.nil_ls.setup({
                on_attach = utils.on_attach,
                cmd = { "nil" },
                capabilities = capabilities,
            })

            -- Python
            lspconfig.pyright.setup({
                on_attach = utils.on_attach,
                cmd = { "pyright-langserver" },
                capabilities = capabilities,
            })

            -- Web
            lspconfig.tsserver.setup({
                on_attach = utils.on_attach,
                capabilities = capabilities,
            })

            lspconfig.emmet_language_server.setup({
                on_attach = utils.on_attach,
                cmd = { "emmet-language-server" },
                capabilities = capabilities,
            })

            lspconfig.tailwindcss.setup({
                on_attach = utils.on_attach,
                cmd = { "tailwindcss-language-server" },
                capabilities = capabilities,
            })

            -- local cssls_capabilities = capabilities
            -- cssls_capabilities.textDocument.completion.completionItem.snippetSupport = true
            -- lspconfig.cssls.setup({
            --     on_attach = utils.on_attach,
            --     capabilities = cssls_capabilities,
            -- })

            -- Zig
            lspconfig.zls.setup({
                capabilities = capabilities,
                cmd = { "zls" },
                on_attach = utils.on_attach,
                settings = {
                    warn_style = true,
                },
            })
        end,
    },
    -- Rust
    {
        "mrcjkb/rustaceanvim",
        version = "^4", -- Recommended
        ft = { "rust" },
        init = function()
            vim.g.rustaceanvim = {
                tools = {
                    enable_clippy = true,
                },
                server = {
                    on_attach = utils.on_attach,
                    default_settings = {
                        ["rust-analyzer"] = {
                            cargo = {
                                allFeatures = true,
                                features = "all",
                                loadOutDirsFromCheck = true,
                                runBuildScripts = true,
                            },
                            -- Add clippy lints for Rust
                            checkOnSave = {
                                allFeatures = true,
                                allTargets = true,
                                command = "clippy",
                                extraArgs = {
                                    "--",
                                    "--no-deps",
                                    "-Dclippy::pedantic",
                                    "-Dclippy::nursery",
                                    "-Dclippy::unwrap_used",
                                    "-Dclippy::enum_glob_use",
                                    "-Wclippy::complexity",
                                    "-Wclippy::perf",
                                    -- Shitty lints imo
                                    "-Aclippy::module_name_repetitions",
                                },
                            },
                            procMacro = {
                                enable = true,
                                ignored = {
                                    ["async-trait"] = { "async_trait" },
                                    ["napi-derive"] = { "napi" },
                                    ["async-recursion"] = { "async_recursion" },
                                },
                            },
                        },
                    },
                },
            }
        end,
    },
}
