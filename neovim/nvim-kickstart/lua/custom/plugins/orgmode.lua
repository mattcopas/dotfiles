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
      local work_todo_file = '~/git/private-work/todo.org'
      local client_todo_file = '~/git/private-client/notes.org'
      local personal_todo_file = '~/git/private-personal/todo.org'
      -- Setup orgmode
      require('orgmode').setup {
        -- TODO - update to what it was in emacs. CAn this be an array?
        org_agenda_files = {
          work_todo_file,
          client_todo_file,
          personal_todo_file,
        },
        org_default_notes_file = '~/orgfiles/refile.org',

        org_capture_templates = {
          p = {
            description = 'Personal Todo',
            template = '* TODO %?',
            target = personal_todo_file,
            headline = 'Todo list',
            properties = { prepend = true },
          },
          w = {
            description = 'Work Todo',
            template = '* TODO %?',
            target = work_todo_file,
            headline = 'Todo list',
            properties = { prepend = true },
          },
          W = {
            description = 'Work Todo - today',
            template = '* TODO %?\n  SCHEDULED: %t',
            target = work_todo_file,
            headline = 'Todo list',
            properties = { prepend = true },
          },
          c = {
            description = 'Client Todo',
            template = '* TODO %?',
            target = client_todo_file,
            headline = 'Stuff to do',
            properties = { prepend = true },
          },
        },

        org_agenda_custom_commands = {
          w = {
            description = 'Work agenda view',
            types = {
              -- 1. High priority unfinished work tasks
              -- Syntax: +work+PRIORITY="A" selects the items, then "/-WAIT-KILL-DONE" filters out those specific TODO states
              {
                type = 'tags',
                match = '+work+PRIORITY="A"/-WAIT-KILL-DONE',
                org_agenda_overriding_header = 'High priority unfinished tasks',
              },

              -- 2. Blocked tasks
              -- Grabs work tasks that are NOT in active states (i.e. everything except TODO, PROGRESS, REVIEW, KILL, DONE)
              {
                type = 'tags_todo',
                match = '+work/-TODO-IN PROGRESS-IN REVIEW-KILL-DONE',
                org_agenda_overriding_header = 'Blocked tasks',
              },

              -- 3. Today's unfinished tasks
              {
                type = 'tags',
                match = 'SCHEDULED="<today>"/-DONE-KILL',
                org_agenda_overriding_header = "Today's tasks",
              },

              -- 4. Today's completed tasks (Only show DONE states)
              {
                type = 'tags',
                match = 'SCHEDULED="<today>"/DONE',
                org_agenda_overriding_header = "Today's completed tasks",
              },

              -- 5. Tomorrow's tasks
              {
                type = 'tags',
                match = 'SCHEDULED="<tomorrow>"',
                org_agenda_overriding_header = "Tomorrow's tasks",
              },

              -- 6. Work Remaining (Non-Priority A, Active items)
              {
                type = 'tags_todo',
                match = '+work-PRIORITY="A"/TODO|IN PROGRESS',
                org_agenda_overriding_header = 'Work Remaining',
              },
            },
          },
        },
      }

      -- Experimental LSP support
      vim.lsp.enable 'org'

      vim.keymap.set('n', '<leader>X', '<cmd>Org capture<cr>', { desc = 'Org Capture Menu' })
    end,
  },
}
