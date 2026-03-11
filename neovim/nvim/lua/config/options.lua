-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
-- Don't show whitespace/tabs etc as underlines
vim.opt.list = false

-- Turn off formatting globally
vim.g.autoformat = false

-- Only underline warnings or worse
vim.diagnostic.config({
  underline = {
    severity = {
      min = vim.diagnostic.severity.WARN,
    },
  },
})
