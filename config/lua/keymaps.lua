-- Better movement
vim.keymap.set({ "n", "v" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
vim.keymap.set({ "n", "v" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

vim.keymap.set("v", "J", ":m '>+1<cr>gv=gv", { silent = true })
vim.keymap.set("v", "K", ":m '<-2<cr>gv=gv", { silent = true })

vim.keymap.set({ "n", "v" }, "<C-d>", "<C-d>zz", { silent = true })
vim.keymap.set({ "n", "v" }, "<C-u>", "<C-u>zz", { silent = true })

vim.keymap.set("n", "n", "nzz")
vim.keymap.set("n", "N", "Nzz")

vim.keymap.set("n", "'", "`")

-- Better line inserting
vim.keymap.set("n", "<leader>o", 'o<Esc>"_D')
vim.keymap.set("n", "<leader>O", 'O<Esc>"_D')

-- Better deleting
vim.keymap.set("n", "<leader>d", '0"_D')

-- Better leaving things
vim.keymap.set("i", "<C-c>", "<Esc>")

-- Quick fix shit

vim.keymap.set("n", "<C-j>", "<cmd>cnext<CR>")
vim.keymap.set("n", "<C-k>", "<cmd>cprev<CR>")

vim.api.nvim_create_user_command("E", function()
    vim.cmd.wa()
    vim.cmd.qa()
end, {})
