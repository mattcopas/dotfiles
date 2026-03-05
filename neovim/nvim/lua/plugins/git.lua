return {
  "NeogitOrg/neogit",
  dependencies = {
    "nvim-lua/plenary.nvim", -- Required
    "sindrets/diffview.nvim", -- Highly recommended for the "Magit" experience
    -- Note that this is an option in LazyExtras - however, that's a preset - having this dep won't update the LazyExtras stuff
    -- To see what plugins are installed, use ::Lazy, not :LazyExtras
    "nvim-telescope/telescope.nvim", -- Optional, but great for searching commits
  },
  config = true,
  keys = {
    -- Mapping <leader>gn for "Git Neogit"
    { "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit" },
  },
}
