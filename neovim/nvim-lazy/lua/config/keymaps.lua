-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Change <leaser><Leadwr> to search for project aware files - instead of those in what ever the termninal $(pwd) is
vim.keymap.set("n", "<leader><leader>", function()
  LazyVim.pick("files")()
end, { desc = "Find Files (Root Aware)" })

-- Write files with <leader>w - update is used instead of write because update only saves
-- if the file has actually been changed (so no pointless timestamp updates etc)
vim.keymap.set("n", "<leader>w", "<cmd>update<cr>", { desc = "Save file if there are changes" })
