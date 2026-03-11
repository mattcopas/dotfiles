-- Don't show whitespace/tabs etc as underlines
vim.opt.list = false

-- Turn off formatting globally
vim.g.autoformat = false

-- Only underline warnings or worse
vim.diagnostic.config({
  underline = {
    severity = {
      min = vim.diagnostic.severity.WARN
    }
  }
})
