" Orgflow: org mode, agenda, journal, which-key menus and project switching.
" Everything else loads on first use, so this file keeps startup fast.
if !has('vim9script') || !has('popupwin') || !has('textprop') || v:version < 900 || exists('g:loaded_orgflow')
  finish
endif
vim9script
g:loaded_orgflow = 1

import autoload 'orgflow/agendaview.vim'
import autoload 'orgflow/capture.vim'
import autoload 'orgflow/journalview.vim'
import autoload 'orgflow/menu.vim'
import autoload 'orgflow/org.vim'
import autoload 'orgflow/projects.vim'

command! OrgflowMenu menu.Open()
command! OrgflowFindFile projects.FindFile()
command! OrgflowSwitchProject projects.SwitchProject()
command! OrgflowSearchProject projects.SearchProject()
command! OrgflowGrep projects.Grep()
command! OrgflowSearchBuffer projects.SearchBuffer()
command! OrgflowBuffers projects.Buffers()
command! OrgflowProjectBuffers projects.ProjectBuffers()
command! OrgflowKillBuffer projects.KillBuffer()
command! OrgflowKillProjectBuffers projects.KillProjectBuffers()
command! OrgflowRevert projects.Revert()
command! OrgflowOpenFile projects.OpenFile()
command! OrgflowRecent projects.Recent()
command! OrgflowGit projects.Git()
command! OrgflowProjectRoot execute 'hide edit' fnameescape(projects.ProjectRoot())

command! -nargs=? OrgCapture capture.Capture(<q-args>)
command! OrgJournal journalview.NewEntry()

command! -nargs=? OrgAgenda agendaview.Open(<q-args>)
command! -bang OrgAgendaOpenItem agendaview.OpenItem(<bang>0)
command! -nargs=1 OrgAgendaShiftDate agendaview.ShiftDate(str2nr(<q-args>))
command! -nargs=1 OrgAgendaWeek agendaview.ShiftWeek(str2nr(<q-args>))
command! OrgAgendaRefresh agendaview.Refresh()
command! OrgAgendaQuit agendaview.Quit()

command! -nargs=? OrgTodo org.SetTodo(<q-args>)
command! -nargs=? OrgSchedule org.Schedule(<q-args>)
command! -nargs=? OrgDeadline org.Deadline(<q-args>)
command! OrgTags org.Tags()
command! OrgPriorityUp org.ChangePriority('up')
command! OrgPriorityDown org.ChangePriority('down')
command! OrgCycle org.Cycle()
command! OrgGlobalCycle org.GlobalCycle()
command! OrgEnter org.Enter()
command! OrgMoveDown org.Move('down')
command! OrgMoveUp org.Move('up')
command! OrgPromote org.Promote(-1, false)
command! OrgDemote org.Promote(1, false)
command! OrgPromoteSubtree org.Promote(-1, true)
command! OrgDemoteSubtree org.Promote(1, true)
command! OrgLink org.InsertLink()
command! OrgAlign org.Align()
command! OrgHeadings org.Headings()

# SPC is the leader. A .vimrc can opt out and bind :OrgflowMenu to something else.
if !exists('g:orgflow_no_leader')
  nnoremap <silent> <Space> <Cmd>OrgflowMenu<CR>
  xnoremap <silent> <Space> <Cmd>OrgflowMenu<CR>
endif

# Most terminals send Alt+j as ESC j. Teaching Vim that makes the Alt bindings work, and
# the short timeout stops a quick Esc then j being taken for Alt+j.
if !has('gui_running') && !exists('g:orgflow_no_meta_keys')
  for key in ['h', 'j', 'k', 'l', 'H', 'L']
    execute "set <M-" .. key .. ">=\<Esc>" .. key
  endfor
  set ttimeout ttimeoutlen=20
endif

augroup orgflow
  autocmd!
  autocmd BufNewFile,BufRead *.org setfiletype org
  autocmd FileType org org.Setup()
  autocmd BufEnter * if exists('b:orgflow_agenda') | agendaview.OnEnter() | endif
  autocmd BufWritePost *.org agendaview.RefreshAll()
augroup END
