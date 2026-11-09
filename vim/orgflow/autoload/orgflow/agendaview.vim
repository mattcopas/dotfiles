vim9script
# Agenda views as read-only scratch buffers, so every motion, search and yank is plain
# Vim, with the org-agenda action keys mapped only in those buffers.
import './agenda.vim'
import './config.vim'
import './date.vim'
import './edits.vim'
import './files.vim'
import './menu.vim'

# Expands agenda entries as org does: directories aren't recursive, and dotfiles are out.
export def CollectPaths(entries: list<string>): list<string>
  var paths: list<string> = []
  for entry in entries
    if isdirectory(entry)
      var names = readdir(entry, (name) => name =~# '^[^.].*\.org$' && !isdirectory(entry .. '/' .. name))
      for name in sort(names)
        var path = substitute(entry, '/$', '', '') .. '/' .. name
        if index(paths, path) < 0
          add(paths, path)
        endif
      endfor
    elseif index(paths, entry) < 0
      add(paths, entry)
    endif
  endfor
  return paths
enddef

def LoadFiles(): list<dict<any>>
  var loaded: list<dict<any>> = []
  var entries = mapnew(config.Get('agenda.files'), (_, path) => config.Expand(path))
  for path in CollectPaths(entries)
    var file = files.Read(path)
    if file.exists
      add(loaded, {path: path, base: fnamemodify(path, ':t:r'), lines: file.lines})
    endif
  endfor
  return loaded
enddef

def Views(): list<dict<any>>
  return config.Get('agenda.views')
enddef

def FindView(key: string): dict<any>
  for view in Views()
    if view.key ==# key
      return view
    endif
  endfor
  return {}
enddef

def SetContents(bufnr: number, lines: list<string>)
  setbufvar(bufnr, '&modifiable', 1)
  files.ApplyToBuffer(bufnr, lines)
  setbufvar(bufnr, '&modifiable', 0)
  setbufvar(bufnr, '&modified', 0)
enddef

def Render(bufnr: number)
  var state: dict<any> = getbufvar(bufnr, 'orgflow_agenda')
  var view = FindView(state.key)
  var rendered: list<any> = []
  try
    if empty(view)
      throw printf('No agenda view with key "%s"', state.key)
    endif
    rendered = agenda.RenderView(view, LoadFiles(), {
      config: config.OrgConfig(),
      clock: date.Now(),
      width: config.Get('agenda.width'),
      weekOffset: state.offset,
      deadlineWarningDays: config.Get('agenda.deadlineWarningDays'),
    })
  catch
    rendered = [{text: 'Agenda view failed: ' .. v:exception}]
  endtry
  state.lines = rendered
  state.stale = false
  SetContents(bufnr, mapnew(rendered, (_, line) => line.text))
enddef

def AgendaBuffers(): list<number>
  var found: list<number> = []
  for info in getbufinfo({bufloaded: 1})
    if type(getbufvar(info.bufnr, 'orgflow_agenda', 0)) == v:t_dict
      add(found, info.bufnr)
    endif
  endfor
  return found
enddef

# Re-renders what's on screen. A hidden agenda catches up when it's next shown.
export def RefreshAll()
  for bufnr in AgendaBuffers()
    if !empty(win_findbuf(bufnr))
      Render(bufnr)
    else
      var state: dict<any> = getbufvar(bufnr, 'orgflow_agenda')
      state.stale = true
    endif
  endfor
enddef

export def OnEnter()
  if exists('b:orgflow_agenda') && b:orgflow_agenda.stale
    Render(bufnr())
  endif
enddef

def SetupBuffer()
  setlocal buftype=nofile bufhidden=hide noswapfile nomodifiable nomodified
  setlocal nowrap nolist nospell nofoldenable nonumber norelativenumber
  setlocal filetype=orgagenda
  nnoremap <buffer> <silent> <CR> <Cmd>OrgAgendaOpenItem<CR>
  nnoremap <buffer> <silent> <Tab> <Cmd>OrgAgendaOpenItem!<CR>
  nnoremap <buffer> <silent> t <Cmd>OrgTodo<CR>
  nnoremap <buffer> <silent> H <Cmd>OrgAgendaShiftDate -1<CR>
  nnoremap <buffer> <silent> L <Cmd>OrgAgendaShiftDate 1<CR>
  nnoremap <buffer> <silent> J <Cmd>OrgPriorityDown<CR>
  nnoremap <buffer> <silent> K <Cmd>OrgPriorityUp<CR>
  nnoremap <buffer> <silent> [[ <Cmd>OrgAgendaWeek -1<CR>
  nnoremap <buffer> <silent> ]] <Cmd>OrgAgendaWeek 1<CR>
  nnoremap <buffer> <silent> r <Cmd>OrgAgendaRefresh<CR>
  nnoremap <buffer> <silent> gr <Cmd>OrgAgendaRefresh<CR>
  nnoremap <buffer> <silent> q <Cmd>OrgAgendaQuit<CR>
  nnoremap <buffer> <silent> C <Cmd>OrgCapture<CR>
enddef

export def Open(key: string = '')
  var chosen = key
  if chosen ==# ''
    var tree = mapnew(Views(), (_, view) => ({key: view.key, name: view.description, value: view.key}))
    var node = menu.Pick(tree, 'Agenda')
    if empty(node)
      return
    endif
    chosen = node.value
  endif
  var view = FindView(chosen)
  if empty(view)
    files.Warn(printf('No agenda view with key "%s"', chosen))
    return
  endif
  var name = '[Agenda ' .. chosen .. '] ' .. view.description
  var existing = bufnr('^' .. escape(name, '[]\.*~^$') .. '$')
  if existing > 0
    execute 'hide buffer' existing
  else
    hide enew
    execute 'silent file' fnameescape(name)
    b:orgflow_agenda = {key: chosen, offset: 0, lines: [], stale: false}
    SetupBuffer()
  endif
  Render(bufnr())
enddef

export def Refresh()
  if exists('b:orgflow_agenda')
    Render(bufnr())
  endif
enddef

export def ShiftWeek(delta: number)
  if exists('b:orgflow_agenda')
    b:orgflow_agenda.offset += delta
    Render(bufnr())
  endif
enddef

# The item under the cursor, or {}.
export def TargetAtCursor(): dict<any>
  if !exists('b:orgflow_agenda')
    return {}
  endif
  var entry = get(b:orgflow_agenda.lines, line('.') - 1, {})
  return get(entry, 'target', {})
enddef

export def IsAgenda(): bool
  return exists('b:orgflow_agenda')
enddef

# Runs an edit on the file behind an agenda line, refusing if that line has changed.
export def EditTarget(target: dict<any>, Edit: func): bool
  var file = files.Read(target.path)
  if !file.exists
    files.Warn('Can''t read ' .. target.path)
    return false
  endif
  if get(file.lines, target.line, v:none) !=# target.raw
    files.Warn('That file has changed. Refreshing the agenda, so try again.')
    RefreshAll()
    return false
  endif
  var after = Edit(file.lines, target.line)
  if empty(after)
    return false
  endif
  files.Write(target.path, after)
  RefreshAll()
  return true
enddef

export def OpenItem(beside: bool)
  var target = TargetAtCursor()
  if empty(target)
    return
  endif
  if beside
    vsplit
  endif
  files.Open(target.path)
  files.Reveal(target.line)
enddef

export def Quit()
  var bufnr = bufnr()
  var alternate = bufnr('#')
  if alternate > 0 && alternate != bufnr && bufexists(alternate) == 1
    execute 'hide buffer' alternate
  else
    hide enew
  endif
enddef

export def ShiftDate(days: number)
  var target = TargetAtCursor()
  if empty(target)
    return
  endif
  if target.kind !=# 'scheduled' && target.kind !=# 'deadline'
    echo 'This item has no scheduled date or deadline here'
    return
  endif
  var label = toupper(target.kind)
  try
    EditTarget(target, (lines, line) => edits.ShiftPlanning(lines, line, label, days, config.OrgConfig()))
  catch
    files.Warn(v:exception)
  endtry
enddef
