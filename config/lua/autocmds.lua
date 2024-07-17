-- vim.api.nvim_create_augroup("File type commands", { clear = false })

-- vim.api.nvim_create_autocmd("FileType", {
--     pattern = "markdown",
--     desc = "Create useful commands in markdown files",
--     callback = function()
--         vim.api.nvim_buf_create_user_command(0, "MarkdownCompile", function()
--             local filename = vim.fn.expand("%")
--             local filename_pdf = vim.fn.expand("%:r") .. ".pdf"
--             local cwd = vim.fn.expand("%:p:h")

--             vim.system({ "pandoc", filename, "-o", filename_pdf, "-V", "geometry:margin=1in" }, { cwd = cwd })
--         end, {})

--         vim.o.wrap = true
--     end,
-- })
