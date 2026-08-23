return {
  {
    'kaiiserni/pinescript.nvim',
    dependencies = {
      'neovim/nvim-lspconfig', -- optional, for LSP features
    },
    ft = 'pine',
    opts = {},
    config = function()
      require('pinescript').setup {
        -- There is a bug in the pinescript plugin here - can be fixed locally by changing the 'LspStart' stuff with vim.lsp.enable('pinescript')
        -- Will put a backwards compatibly PR in that either uses the modern version (0.11+ ?) if available, or falls back to the current/old way to enable
        -- The plugin uses LspStart pinescript - which was changed in nvim 0.12 to vim.lsp.enable('pinescript')
        -- This needs fixing at the plugin level - I could fork and fix
        lsp = {
          enabled = true,
          auto_install = true,
        },
        treesitter = {
          enabled = true,
          auto_install = true,
        },
      }
    end,
  },
}
