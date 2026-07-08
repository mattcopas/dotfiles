-- For these plugin files, we return a table (the first set of brackets).
-- Tables in lua can be:
--   Arrays: {"a", "b", 3} - note that these are 1-indexed ! ie my_array[1] will be "a"
--   Dictionaries: { foo = "bar", baz = {"some", "array"} }
--   Mixed: mixed =  {"a", "b", foo = "bar", baz = {"some", "array"} }  - access with mixed[1] or mixed.foo or mixed["foo"].
-- So, we return a table (an array in this case) - which is made oup of mixed tables
return {
  {
    'nvim-orgmode/orgmode',
    event = 'VeryLazy',
    ft = { 'org' },
    config = function()
      -- Setup orgmode
      require('orgmode').setup {
        org_agenda_files = '~/orgfiles/**/*',
        org_default_notes_file = '~/orgfiles/refile.org',
      }

      -- Experimental LSP support
      vim.lsp.enable 'org'
    end,
  },
}
