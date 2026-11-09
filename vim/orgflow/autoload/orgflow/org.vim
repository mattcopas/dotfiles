vim9script
# Commands that act on "the current heading", which is either the heading around the
# cursor in an org file or the item under the cursor in an agenda.
import './agendaview.vim'
import './config.vim'
import './date.vim'
import './edits.vim'
import './files.vim'
import './fold.vim'
import './menu.vim'
import './parser.vim'
import './picker.vim'
import './table.vim'
import './timestamp.vim' as ts

def IsOrg(): bool
  return &filetype ==# 'org'
enddef

# Applies an edit to the heading under the cursor, in whichever kind of buffer.
def EditCurrentHeading(Edit: func)
  try
    var target = agendaview.TargetAtCursor()
    if !empty(target)
      agendaview.EditTarget(target, Edit)
      return
    endif
    if agendaview.IsAgenda()
      echo 'Not on an agenda item'
      return
    endif
    if !IsOrg()
      echo 'Not on an org heading'
      return
    endif
    var lines = files.BufferLines(bufnr())
    var heading = parser.HeadingAt(parser.ParseOrg(lines, config.OrgConfig()), line('.') - 1)
    if empty(heading)
      echo 'Before the first heading'
      return
    endif
    var after = Edit(lines, heading.line)
    if !empty(after)
      files.ApplyToBuffer(bufnr(), after)
    endif
  catch
    files.Warn(v:exception)
  endtry
enddef

def KeywordTree(): list<any>
  var cfg = config.OrgConfig()
  var used: dict<bool> = {}
  for sequence in cfg.sequences
    for name in sequence.todo + sequence.done
      if has_key(cfg.keys, name)
        used[cfg.keys[name]] = true
      endif
    endfor
  endfor
  var tree: list<any> = []
  var spare = 1
  for sequence in cfg.sequences
    for name in sequence.todo + sequence.done
      var key: string = get(cfg.keys, name, '')
      # Keywords with no hotkey, such as LOOP, still need to be reachable from here.
      if key ==# ''
        while has_key(used, string(spare))
          spare += 1
        endwhile
        key = string(spare % 10)
        used[key] = true
      endif
      add(tree, {key: key, name: name, value: name})
    endfor
  endfor
  add(tree, {key: ' ', name: 'Clear keyword', value: ''})
  return tree
enddef

export def SetTodo(keyword: string)
  var chosen = keyword
  if chosen ==# ''
    if empty(agendaview.TargetAtCursor()) && !IsOrg()
      echo 'Not on an org heading'
      return
    endif
    var node = menu.Pick(KeywordTree(), 'TODO state')
    if empty(node)
      return
    endif
    chosen = node.value
  endif
  var word = chosen
  EditCurrentHeading((lines, line) => edits.SetTodo(lines, line, word, config.OrgConfig(), date.Now()))
enddef

def ScheduleOn(label: string, input: string)
  var parsed = ts.ParseDateInput(input, date.Now().today)
  if empty(parsed)
    files.Warn(printf('Can''t read the date "%s"', input))
    return
  endif
  EditCurrentHeading((lines, line) => edits.SetPlanning(lines, line, label, parsed.abs, parsed.minutes, config.OrgConfig()))
enddef

def SetPlanningCommand(label: string, title: string, input: string)
  if input !=# ''
    ScheduleOn(label, input)
    return
  endif
  while true
    var typed = input(title .. ' (+1d, fri, 2026-11-12, tomorrow 14:30): ')
    if typed ==# ''
      return
    endif
    if !empty(ts.ParseDateInput(typed, date.Now().today))
      ScheduleOn(label, typed)
      return
    endif
    redraw
    echo printf('Can''t read "%s". ', typed)
  endwhile
enddef

export def Schedule(input: string)
  SetPlanningCommand('SCHEDULED', 'Schedule for', input)
enddef

export def Deadline(input: string)
  SetPlanningCommand('DEADLINE', 'Deadline', input)
enddef

export def Tags()
  if !IsOrg()
    return
  endif
  var doc = parser.ParseOrg(files.BufferLines(bufnr()), config.OrgConfig())
  var heading = parser.HeadingAt(doc, line('.') - 1)
  if empty(heading)
    return
  endif
  # input() returns '' for both an empty answer and Esc, so removing tags asks first.
  var value = input('Tags (a:b): ', join(heading.localTags, ':'))
  if value ==# '' && (empty(heading.localTags) || confirm('Remove all tags?', "&Yes\n&No", 2) != 1)
    return
  endif
  var tags = filter(split(value, '[:[:space:]]\+'), (_, tag) => tag !=# '')
  EditCurrentHeading((lines, line) => edits.SetTags(lines, line, tags, config.OrgConfig()))
enddef

export def ChangePriority(direction: string)
  EditCurrentHeading((lines, line) => edits.ChangePriority(lines, line, direction, config.OrgConfig()))
enddef

# Runs a structure edit if the cursor is on a heading.
def StructureCommand(Run: func): bool
  var lnum = line('.')
  if empty(parser.ParseHeadingLine(getline(lnum), config.OrgConfig()))
    return false
  endif
  try
    var column = col('.')
    var before = getline(lnum)
    var result = Run(files.BufferLines(bufnr()), lnum - 1)
    if type(result) == v:t_dict
      files.ApplyToBuffer(bufnr(), result.lines)
      cursor(result.line + 1, column)
    else
      files.ApplyToBuffer(bufnr(), result)
      cursor(lnum, column + strlen(getline(lnum)) - strlen(before))
    endif
    silent! normal! zv
  catch
    files.Warn(v:exception)
  endtry
  return true
enddef

# Off a heading, Alt+j and Alt+k drag the line, as org-metadown does on plain text.
export def Move(direction: string)
  if !IsOrg()
    return
  endif
  var moved = StructureCommand((lines, line) => edits.MoveSubtree(lines, line, direction, config.OrgConfig()))
  if !moved
    if direction ==# 'down' && line('.') < line('$')
      silent! move +1
    elseif direction ==# 'up' && line('.') > 1
      silent! move -2
    endif
  endif
enddef

export def Promote(delta: number, subtree: bool)
  if !IsOrg()
    return
  endif
  if subtree
    StructureCommand((lines, line) => edits.ShiftSubtree(lines, line, delta, config.OrgConfig()))
  else
    StructureCommand((lines, line) => edits.ShiftHeading(lines, line, delta, config.OrgConfig()))
  endif
enddef

# Indenting a heading changes its stars, as evil-org does: a range that starts on a
# heading shifts its headings, and any other range indents as usual.
def ShiftRange(first: number, last: number, delta: number)
  var column = col('.')
  var cfg = config.OrgConfig()
  if empty(parser.ParseHeadingLine(getline(first), cfg)) && empty(parser.ParseHeadingLine(getline('.'), cfg))
    execute printf('silent :%d,%d%s', first, last, delta > 0 ? '>' : '<')
    return
  endif
  var lines = files.BufferLines(bufnr())
  var after = edits.ShiftHeadings(lines, first - 1, last - 1, delta, cfg)
  if after == lines
    echo 'Already at the top level'
    return
  endif
  files.ApplyToBuffer(bufnr(), after)
  cursor(first, first == last ? max([1, column + delta]) : 1)
  silent! normal! zv
enddef

export def ShiftRightOperator(_: string)
  ShiftRange(line("'["), line("']"), 1)
enddef

export def ShiftLeftOperator(_: string)
  ShiftRange(line("'["), line("']"), -1)
enddef

# Going through an operator makes counts, motions and `.` work as they do for > and <.
export def ShiftOperator(delta: number): string
  &operatorfunc = delta > 0 ? 'orgflow#org#ShiftRightOperator' : 'orgflow#org#ShiftLeftOperator'
  return 'g@'
enddef

export def ShiftVisual(delta: number)
  var first = min([line('v'), line('.')])
  var last = max([line('v'), line('.')])
  execute "normal! \<Esc>"
  ShiftRange(first, last, delta)
enddef

# TAB and S-TAB on a heading in Insert mode, with the cursor staying on the same text.
def ShiftInInsert(delta: number)
  var lnum = line('.')
  var lines = files.BufferLines(bufnr())
  var after = edits.ShiftHeadings(lines, lnum - 1, lnum - 1, delta, config.OrgConfig())
  if after != lines
    var column = col('.')
    files.ApplyToBuffer(bufnr(), after)
    cursor(lnum, column + delta)
  endif
enddef

def TableTab()
  var lnum = line('.')
  var lines = files.BufferLines(bufnr())
  var aligned = table.AlignTableAt(lines, lnum - 1)
  var next = table.NextCell(aligned, lnum - 1, col('.') - 1)
  if next.addRow
    aligned = slice(aligned, 0, next.line) + [table.BlankRow(aligned[lnum - 1])] + slice(aligned, next.line)
    next.column = 2
  endif
  files.ApplyToBuffer(bufnr(), aligned)
  cursor(next.line + 1, next.column + 1)
enddef

export def Cycle()
  var lnum = line('.')
  if foldclosed(lnum) > 0
    fold.OpenClosed(lnum)
    return
  endif
  var text = getline(lnum)
  if table.IsTableLine(text)
    TableTab()
    return
  endif
  if parser.IsHeadingLine(text)
    echo fold.Cycle(lnum)
    return
  endif
  if text =~? '^\s*\(#+begin_\|:\(PROPERTIES\|LOGBOOK\):\)'
    normal! za
    return
  endif
  # Terminals send the same code for TAB and Ctrl-i, so elsewhere it keeps Vim's meaning.
  # The count matters: :normal strips a leading Ctrl-i as whitespace and then fails.
  execute "silent! normal! 1\<C-i>"
enddef

# In Insert mode TAB moves between table cells, and is an ordinary TAB anywhere else.
export def InsertTab()
  if table.IsTableLine(getline('.'))
    TableTab()
  elseif parser.IsHeadingLine(getline('.'))
    ShiftInInsert(1)
  else
    feedkeys("\<Tab>", 'nt')
  endif
enddef

export def InsertShiftTab()
  if parser.IsHeadingLine(getline('.'))
    ShiftInInsert(-1)
  else
    feedkeys("\<S-Tab>", 'nt')
  endif
enddef

export def GlobalCycle()
  echo fold.GlobalCycle()
enddef

export def Align()
  if IsOrg()
    files.ApplyToBuffer(bufnr(), table.AlignTableAt(files.BufferLines(bufnr()), line('.') - 1))
  endif
enddef

# --- links -----------------------------------------------------------------

# Links in a line as {start, end, target}, in bytes from 0, with `end` exclusive.
export def FindLinks(line: string): list<dict<any>>
  var links: list<dict<any>> = []
  var from = 0
  while true
    var found = matchstrpos(line, '\C\v\[\[[^\]]+\]%(\[[^\]]*\])?\]', from)
    if found[1] < 0
      break
    endif
    add(links, {start: found[1], end: found[2], target: matchlist(found[0], '\v^\[\[([^\]]+)\]')[1]})
    from = found[2]
  endwhile
  from = 0
  while true
    var found = matchstrpos(line, '\C\vhttps?://[^ \t\]>)]+', from)
    if found[1] < 0
      break
    endif
    var start: number = found[1]
    if empty(filter(copy(links), (_, link) => start >= link.start && start < link.end))
      add(links, {start: start, end: found[2], target: found[0]})
    endif
    from = found[2]
  endwhile
  return links
enddef

def SearchLine(search: string): number
  var doc = parser.ParseOrg(files.BufferLines(bufnr()), config.OrgConfig())
  if strpart(search, 0, 1) ==# '*'
    var title = substitute(search, '^\*\+\s*', '', '')
    for heading in doc.headings
      if heading.title ==# title
        return heading.line
      endif
    endfor
    return -1
  endif
  if strpart(search, 0, 1) ==# '#'
    var id = strpart(search, 1)
    for heading in doc.headings
      if get(heading.properties, 'CUSTOM_ID', '') ==# id
        return heading.line
      endif
    endfor
    return -1
  endif
  if search =~# '^\d\+$'
    return str2nr(search) - 1
  endif
  var at = 0
  for line in doc.lines
    if stridx(line, search) >= 0
      return at
    endif
    at += 1
  endfor
  return -1
enddef

def OpenExternal(target: string)
  var opener = has('mac') || has('macunix') ? 'open' : 'xdg-open'
  if executable(opener) != 1
    files.Warn('No ' .. opener .. ' command to open ' .. target)
    return
  endif
  job_start([opener, target], {in_io: 'null', out_io: 'null', err_io: 'null', stoponexit: ''})
enddef

export def FollowLink(target: string)
  if target =~# '\v^%(https?|mailto):'
    OpenExternal(target)
    return
  endif
  var search = ''
  var path = expand('%:p')
  if target =~# '^[*#]'
    search = target
  else
    var pieces = split(substitute(target, '\C\v^file%(\+[a-z]+)?:', '', ''), '::', 1)
    var name = config.Expand(pieces[0])
    if name !=# ''
      path = name =~# '^/' ? name : expand('%:p:h') .. '/' .. name
    endif
    search = get(pieces, 1, '')
  endif
  if path !=# expand('%:p')
    files.Open(path)
  endif
  if search !=# ''
    var line = SearchLine(search)
    if line < 0
      files.Warn('Couldn''t find ' .. search)
    else
      files.Reveal(line)
    endif
  endif
enddef

# Enter follows the link under the cursor, and otherwise does what it normally does.
export def Enter()
  var column = col('.') - 1
  for link in FindLinks(getline('.'))
    if column >= link.start && column < link.end
      FollowLink(link.target)
      return
    endif
  endfor
  execute "normal! \<CR>"
enddef

export def InsertLink()
  if !IsOrg()
    return
  endif
  var target = input('Link (https://example.com, file:notes.org, *Heading): ')
  if target ==# ''
    return
  endif
  var description = input('Description (optional): ')
  var text = description !=# '' ? printf('[[%s][%s]]', target, description) : printf('[[%s]]', target)
  var line = getline('.')
  var column = col('.')
  setline('.', strpart(line, 0, column) .. text .. strpart(line, column))
enddef

export def Headings()
  if !IsOrg()
    return
  endif
  var doc = parser.ParseOrg(files.BufferLines(bufnr()), config.OrgConfig())
  var chosen = picker.Pick({
    title: 'Headings',
    items: mapnew(doc.headings, (_, h) => ({text: repeat('*', h.level) .. ' ' .. h.text, lnum: h.line})),
  })
  if !empty(chosen)
    files.Reveal(chosen.item.lnum)
  endif
enddef

# Org buffer settings, run from the FileType autocommand. This doesn't depend on
# `filetype plugin on`, so a minimal .vimrc works.
export def Setup()
  setlocal foldmethod=expr
  setlocal foldexpr=orgflow#fold#Expr()
  setlocal foldtext=orgflow#fold#Text()
  setlocal foldminlines=0
  &l:fillchars = trim(substitute(&fillchars, '\%(^\|,\)fold:[^,]*', '', '') .. ',fold: ', ',', 1)
  setlocal wrap linebreak breakindent
  setlocal autoread
  setlocal commentstring=#\ %s
  setlocal nosmartindent
  if !exists('b:orgflow_setup')
    b:orgflow_setup = true
    execute 'setlocal foldlevel=' .. (config.Get('startupFolded') ? 0 : 99)
    execute 'setlocal conceallevel=' .. (config.Get('hideMarkup') ? 2 : 0)
    setlocal concealcursor=
  endif

  augroup orgflow_buffer
    autocmd! * <buffer>
    autocmd InsertEnter <buffer> call orgflow#fold#InsertEnter()
    autocmd InsertLeave <buffer> call orgflow#fold#InsertLeave()
  augroup END

  nnoremap <buffer> <silent> <Tab> <Cmd>OrgCycle<CR>
  nnoremap <buffer> <silent> <S-Tab> <Cmd>OrgGlobalCycle<CR>
  nnoremap <buffer> <silent> <CR> <Cmd>OrgEnter<CR>
  inoremap <buffer> <silent> <Tab> <Cmd>call orgflow#org#InsertTab()<CR>
  inoremap <buffer> <silent> <S-Tab> <Cmd>call orgflow#org#InsertShiftTab()<CR>
  nnoremap <buffer> <silent> <expr> > orgflow#org#ShiftOperator(1)
  nnoremap <buffer> <silent> <expr> <lt> orgflow#org#ShiftOperator(-1)
  nnoremap <buffer> <silent> <expr> >> orgflow#org#ShiftOperator(1) .. '_'
  nnoremap <buffer> <silent> <expr> <lt><lt> orgflow#org#ShiftOperator(-1) .. '_'
  xnoremap <buffer> <silent> > <Cmd>call orgflow#org#ShiftVisual(1)<CR>
  xnoremap <buffer> <silent> <lt> <Cmd>call orgflow#org#ShiftVisual(-1)<CR>
  nnoremap <buffer> <silent> <M-j> <Cmd>OrgMoveDown<CR>
  nnoremap <buffer> <silent> <M-k> <Cmd>OrgMoveUp<CR>
  nnoremap <buffer> <silent> <M-h> <Cmd>OrgPromote<CR>
  nnoremap <buffer> <silent> <M-l> <Cmd>OrgDemote<CR>
  nnoremap <buffer> <silent> <M-H> <Cmd>OrgPromoteSubtree<CR>
  nnoremap <buffer> <silent> <M-L> <Cmd>OrgDemoteSubtree<CR>
enddef
