vim9script
# The editor layer in a real Vim: buffers, folds, file safety, agenda, capture, journal
# and settings. Real keystrokes are covered by test/e2e.py. Run through test/run.sh.
set ignorecase smartcase nomore
source <script>:h/../plugin/orgflow.vim

import autoload 'orgflow/agendaview.vim'
import autoload 'orgflow/capture.vim'
import autoload 'orgflow/config.vim'
import autoload 'orgflow/date.vim'
import autoload 'orgflow/files.vim'
import autoload 'orgflow/fold.vim'
import autoload 'orgflow/journal.vim'
import autoload 'orgflow/journalview.vim'
import autoload 'orgflow/menu.vim'
import autoload 'orgflow/org.vim'
import autoload 'orgflow/projects.vim'

const work: string = g:orgflow_work .. '/editor'
mkdir(work, 'p')
g:orgflow_test_clock = {today: date.ToAbs(2026, 11, 11), minutes: 630}
g:orgflow_settings_file = work .. '/no-settings.json'
const shared: string = g:orgflow_shared_tests

var passed = 0
var failures: list<string> = []

def Check(name: string, got: any, want: any)
  if type(got) == type(want) && got == want
    passed += 1
    return
  endif
  add(failures, printf("FAIL %s\n  got:  %s\n  want: %s", name, string(got), string(want)))
enddef

def Fresh(name: string, text: string): string
  var path = work .. '/' .. name
  mkdir(fnamemodify(path, ':h'), 'p')
  writefile(split(text, "\n", 1), path, 'b')
  return path
enddef

def Raw(path: string): string
  return join(readfile(path, 'b'), "\n")
enddef

def Reset()
  silent! :%bwipeout!
enddef

# --- settings --------------------------------------------------------------
def TestSettings()
  Check('strips comments', config.StripJsonc("{\n // note\n \"a\": 1, /* x */\n \"b\": [1, 2,],\n}\n")->json_decode(), {a: 1, b: [1, 2]})
  Check('keeps // in strings', config.StripJsonc('{"a": "http://x", "b": "c,]"}')->json_decode(), {a: 'http://x', b: 'c,]'})
  Check('default', config.Get('journal.fileFormat'), '%b-%Y.org')
  var file = Fresh('settings.json', "{\n  // comment\n  \"editor.fontSize\": 12,\n  \"orgflow.journal.directory\": \"~/j\",\n  \"orgflow.agenda.width\": 77,\n}\n")
  g:orgflow_settings_file = file
  Check('from settings.json', config.Get('journal.directory'), '~/j')
  Check('other keys ignored', config.Get('editor.fontSize', 'none'), 'none')
  g:orgflow = {'agenda.width': 90}
  Check('g:orgflow wins', config.Get('agenda.width'), 90)
  Check('fallback for Vim-only', config.Get('whichKey.delay', 700), 700)
  unlet g:orgflow
  g:orgflow_settings_file = work .. '/no-settings.json'
  Check('expand', config.Expand('~/x'), $HOME .. '/x')
enddef
TestSettings()

# --- files -----------------------------------------------------------------
def TestFiles()
  Reset()
  var path = Fresh('crlf.org', "* a\r\nbody\r\n")
  Check('read strips CR', files.Read(path).lines, ['* a', 'body', ''])
  files.Write(path, ['* a', 'body', 'more', ''])
  Check('write keeps CRLF', Raw(path), "* a\r\nbody\r\nmore\r\n")
  var plain = Fresh('plain.org', "* a\nno final newline")
  files.Write(plain, ['* b', 'no final newline'])
  Check('write keeps no final newline', Raw(plain), "* b\nno final newline")

  # A clean buffer follows the disk, and an outside change isn't overwritten.
  var clean = Fresh('clean.org', "* a\nb\n")
  execute 'edit' clean
  writefile(['* outside', 'b', ''], clean, 'b')
  Check('clean buffer reads disk', files.Read(clean).lines, ['* outside', 'b', ''])
  files.Write(clean, ['* outside', 'b', 'c', ''])
  Check('clean write reaches disk', Raw(clean), "* outside\nb\nc\n")
  Check('clean buffer reloads', getline(1, '$'), ['* outside', 'b', 'c'])
  Check('and stays clean', &modified, false)
  files.Write(clean, ['* inside', 'b', 'c', ''])
  Check('same-size change reloads', getline(1), '* inside')
  Reset()

  # Unsaved work stays unsaved, in the buffer, and the disk isn't touched.
  var dirty = Fresh('dirty.org', "* a\n")
  execute 'edit' dirty
  setline(1, '* unsaved')
  Check('dirty read wins', files.Read(dirty).lines, ['* unsaved', ''])
  files.Write(dirty, ['* unsaved', '* more', ''])
  Check('dirty buffer edited', getline(1, '$'), ['* unsaved', '* more'])
  Check('dirty stays unsaved', &modified, true)
  Check('dirty disk untouched', Raw(dirty), "* a\n")
  set nomodified
  Reset()

  # New files, in directories that don't exist yet.
  var fresh = work .. '/new/deep/file.org'
  Check('missing file', files.Read(fresh), {lines: [''], exists: false})
  files.Write(fresh, ['* x', ''])
  Check('creates directories', Raw(fresh), "* x\n")
enddef
TestFiles()

# --- minimal application -----------------------------------------------------
def TestApply()
  Reset()
  enew
  setline(1, ['a', 'b', 'c', 'd'])
  var bufnr = bufnr()
  files.ApplyToBuffer(bufnr, ['a', 'X', 'c', 'd', ''])
  Check('replace', getline(1, '$'), ['a', 'X', 'c', 'd'])
  files.ApplyToBuffer(bufnr, ['a', 'c', 'd', ''])
  Check('delete', getline(1, '$'), ['a', 'c', 'd'])
  files.ApplyToBuffer(bufnr, ['a', 'new', 'lines', 'c', 'd', ''])
  Check('insert', getline(1, '$'), ['a', 'new', 'lines', 'c', 'd'])
  files.ApplyToBuffer(bufnr, ['a', 'new', 'lines', 'c', 'd'])
  Check('no final newline', &endofline, false)
  files.ApplyToBuffer(bufnr, ['a', 'new', 'lines', 'c', 'd', ''])
  Check('final newline back', &endofline, true)
  set nomodified
enddef
TestApply()

# --- folding ---------------------------------------------------------------
const FOLD_TEXT = "#+TITLE: t\n* One\nbody one\n** Child\nchild body\n** Second\n*** Deep\ndeep body\n* Two\n:PROPERTIES:\n:ID: x\n:END:\nbody two\n* Empty\n* Parent with body\nintro 1\nintro 2\n** Kid\n"

def ClosedLines(): list<number>
  var closed: list<number> = []
  var lnum = 1
  while lnum <= line('$')
    var start = foldclosed(lnum)
    if start > 0
      add(closed, start)
      lnum = foldclosedend(lnum) + 1
    else
      lnum += 1
    endif
  endwhile
  return closed
enddef

def TestFolds()
  Reset()
  var path = Fresh('folds.org', FOLD_TEXT)
  execute 'edit' path
  Check('filetype', &filetype, 'org')
  # Headings are never folded, so they keep their colours: only their content is.
  Check('starts in overview', ClosedLines(), [3, 10, 16])
  Check('top-level headings show', [foldclosed(2), foldclosed(9), foldclosed(14), foldclosed(15)], [-1, -1, -1, -1])

  # TAB on One: FOLDED, then CHILDREN, then SUBTREE, then FOLDED.
  cursor(2, 1)
  Check('children state', fold.Cycle(2), 'CHILDREN')
  Check('children hide bodies', ClosedLines(), [3, 5, 7, 10, 16])
  Check('children headings show', [foldclosed(4), foldclosed(6)], [-1, -1])
  Check('subtree state', fold.Cycle(2), 'SUBTREE')
  Check('subtree shows all', ClosedLines(), [10, 16])
  Check('folded state', fold.Cycle(2), 'FOLDED')
  Check('folded', ClosedLines(), [3, 10, 16])
  Check('the closed fold covers the subtree', foldclosedend(3), 8)
  Check('cycle repeats', fold.Cycle(2), 'CHILDREN')

  # A leaf has no CHILDREN step, and a drawer stays shut when its entry opens.
  Check('leaf opens', fold.Cycle(9), 'SUBTREE')
  Check('drawer stays closed', foldclosed(10), 10)
  Check('body visible', foldclosed(13), -1)
  Check('leaf closes', fold.Cycle(9), 'FOLDED')
  Check('leaf content closes whole', [foldclosed(10), foldclosedend(10)], [10, 13])

  # A heading with nothing under it has nothing to cycle.
  Check('empty heading', fold.Cycle(14), 'EMPTY')

  # A parent's own body folds separately, which VS Code couldn't do.
  Check('parent body opens', fold.Cycle(15), 'CHILDREN')
  Check('parent body is folded', foldclosed(16), 16)
  Check('child heading visible', foldclosed(18), -1)

  # TAB on the row of a closed fold opens it.
  normal! zM
  cursor(3, 1)
  execute 'OrgCycle'
  Check('TAB on a closed row opens it', ClosedLines(), [10, 16])
  Check('and lands on its first line', line('.'), 3)

  # Global cycle.
  normal! zM
  Check('contents', fold.GlobalCycle(), 'CONTENTS')
  Check('contents shows all headings', [foldclosed(2), foldclosed(4), foldclosed(7), foldclosed(9), foldclosed(14), foldclosed(15), foldclosed(18)], [-1, -1, -1, -1, -1, -1, -1])
  Check('contents hides bodies', [foldclosed(3), foldclosed(5), foldclosed(8), foldclosed(10), foldclosed(16)], [3, 5, 8, 10, 16])
  Check('show all', fold.GlobalCycle(), 'SHOW ALL')
  Check('show all keeps drawers', ClosedLines(), [10])
  Check('overview', fold.GlobalCycle(), 'OVERVIEW')
  Check('back to overview', ClosedLines(), [3, 10, 16])

  # Nesting several levels deep, with each kind of first line.
  var deep = Fresh('deep.org', "* A\n** B\n*** C\nc body\n** D\n:PROPERTIES:\n:ID: 1\n:END:\nd body\n*** E\n* F\n")
  execute 'edit' deep
  Check('deep overview', ClosedLines(), [2])
  Check('deep closed fold reaches the next top heading', foldclosedend(2), 10)
  Check('a child straight under a parent', fold.Cycle(1), 'CHILDREN')
  Check('both children show', [foldclosed(2), foldclosed(5)], [-1, -1])
  Check('with their content closed', [foldclosedend(3), foldclosedend(6)], [4, 10])
  Check('then the whole subtree', fold.Cycle(1), 'SUBTREE')
  Check('apart from the drawer', ClosedLines(), [6])
  Check('then folded', fold.Cycle(1), 'FOLDED')
  Check('all under A', foldclosedend(2), 10)
  Reset()
enddef
TestFolds()

# --- org commands in a buffer ------------------------------------------------
def TestOrgCommands()
  Reset()
  var path = Fresh('cmd.org', "* TODO First :a:\nbody\n* Second\n** Child\n* Third\n")
  execute 'edit' path
  normal! zR
  cursor(2, 1)
  execute 'OrgTodo DONE'
  Check('todo from the body', getline(1), '* DONE First :a:')
  Check('edit leaves it unsaved', &modified, true)
  Check('and off disk', Raw(path), "* TODO First :a:\nbody\n* Second\n** Child\n* Third\n")
  execute 'OrgTodo IN PROGRESS'
  Check('keyword with a space', getline(1), '* IN PROGRESS First :a:')
  execute 'OrgSchedule +1d'
  Check('schedule', getline(2), 'SCHEDULED: <2026-11-12 Thu>')
  execute 'OrgDeadline 2026-12-01'
  Check('deadline', getline(2), 'SCHEDULED: <2026-11-12 Thu> DEADLINE: <2026-12-01 Tue>')
  # Inside a script all changes share one undo step, so mark where a typed command starts.
  &undolevels = &undolevels
  execute 'OrgPriorityUp'
  Check('priority', getline(1), '* IN PROGRESS [#B] First :a:')
  undo
  Check('one undo per command', getline(1), '* IN PROGRESS First :a:')

  cursor(4, 3)
  execute 'OrgMoveDown'
  Check('move down', getline(1, '$'), ['* IN PROGRESS First :a:', 'SCHEDULED: <2026-11-12 Thu> DEADLINE: <2026-12-01 Tue>', 'body', '* Third', '* Second', '** Child'])
  Check('cursor follows', line('.'), 5)
  execute 'OrgMoveUp'
  Check('move up', getline(4), '* Second')
  cursor(5, 1)
  execute 'OrgDemote'
  Check('demote heading', getline(5), '*** Child')
  execute 'OrgPromote'
  Check('promote heading', getline(5), '** Child')
  cursor(4, 1)
  execute 'OrgDemoteSubtree'
  Check('demote subtree', getline(4, 5), ['** Second', '*** Child'])
  execute 'OrgPromoteSubtree'
  execute 'OrgPromote'
  Check('level 1 stays', getline(4), '* Second')

  cursor(3, 1)
  execute 'OrgMoveDown'
  Check('moving a body line drags it', getline(3, 4), ['* Second', 'body'])
  set nomodified
  Reset()

  execute 'edit' Fresh('table.org', "* T\n|a|bbb|\n|--\n|cc|1|\n")
  normal! zR
  cursor(2, 2)
  execute 'OrgCycle'
  Check('TAB aligns', getline(2, 4), ['| a  | bbb |', '|----+-----|', '| cc | 1   |'])
  Check('and moves a cell', col('.'), 3)
  execute 'OrgCycle'
  Check('to the next one', col('.'), 8)
  execute 'OrgCycle'
  Check('skips the rule', [line('.'), col('.')], [4, 3])
  cursor(4, 8)
  execute 'OrgCycle'
  Check('adds a row', getline(5), '|    |     |')
  Check('at its first cell', [line('.'), col('.')], [5, 3])
  set nomodified
  Reset()

  execute 'edit' Fresh('plain.org', "* TODO Item\nSCHEDULED: <2026-11-11 Wed>\nbody\n")
  normal! zR
  cursor(2, 1)
  var cycleError = ''
  try
    execute 'OrgCycle'
  catch
    cycleError = v:exception
  endtry
  Check('TAB on a SCHEDULED line raises no error', cycleError, '')
  Check('and stays there', line('.'), 2)
  Reset()

  # Indenting a heading changes its stars, and any other line indents as usual.
  execute 'edit' Fresh('shift.org', "* One\nbody\n** Two\n* Three\n")
  normal! zR
  set shiftwidth=2 expandtab
  cursor(1, 1)
  feedkeys('>>', 'tx')
  Check('>> adds a star', getline(1), '** One')
  feedkeys('.', 'tx')
  Check('. repeats it', getline(1), '*** One')
  feedkeys('<<<<', 'tx')
  Check('<< removes them', getline(1), '* One')
  feedkeys('<<', 'tx')
  Check('<< stops at one star', getline(1), '* One')
  cursor(2, 1)
  feedkeys('>>', 'tx')
  Check('>> on a body line indents', getline(2), '  body')
  feedkeys('<<', 'tx')
  Check('<< on a body line unindents', getline(2), 'body')
  cursor(1, 1)
  feedkeys('3>>', 'tx')
  Check('a count covers its lines', getline(1, 4), ['** One', 'body', '*** Two', '* Three'])
  feedkeys('3<<', 'tx')
  cursor(1, 1)
  feedkeys('>G', 'tx')
  Check('a motion works', getline(1, 4), ['** One', 'body', '*** Two', '** Three'])
  feedkeys('<G', 'tx')
  cursor(1, 1)
  feedkeys('Vjjj>', 'tx')
  Check('Visual > shifts headings only', getline(1, 4), ['** One', 'body', '*** Two', '** Three'])
  cursor(1, 1)
  feedkeys('Vjjj<', 'tx')
  Check('Visual < shifts them back', getline(1, 4), ['* One', 'body', '** Two', '* Three'])
  cursor(2, 1)
  feedkeys('V>', 'tx')
  Check('Visual > on a body line indents it', getline(2), '  body')
  feedkeys('u', 'tx')
  cursor(3, 1)
  feedkeys("A\<Tab>X\<Esc>", 'tx')
  Check('Insert TAB adds a star and keeps the cursor', getline(3), '*** TwoX')
  feedkeys("A\<S-Tab>Y\<Esc>", 'tx')
  Check('Insert S-TAB removes one', getline(3), '** TwoXY')
  set shiftwidth& expandtab&
  set nomodified
  Reset()

  # A window keeps its fillchars, so a second org file used to stop Setup part way.
  execute 'edit' Fresh('first.org', "* One\n")
  execute 'edit' Fresh('second.org', "* Two\n")
  Check('a second org file in the window still gets set up', maparg('<Tab>', 'n') =~# 'OrgCycle', true)
  Check('and has one fold fill character', len(matchlist(&l:fillchars, 'fold: ')) > 0 && &l:fillchars !~# ',,', true)
  Reset()
enddef
TestOrgCommands()

# --- links -----------------------------------------------------------------
def TestLinks()
  Reset()
  Check('finds links', mapnew(org.FindLinks('a [[https://x.y][d]] b [[*Head]] https://z.a/b. c'), (_, l) => l.target), ['https://x.y', '*Head', 'https://z.a/b.'])
  var target = Fresh('links/target.org', "* Intro\n* Wanted\n:PROPERTIES:\n:CUSTOM_ID: myid\n:END:\nfind this text\n")
  var path = Fresh('links/source.org', "* Link [[*Other]]\n[[file:target.org::*Wanted]]\n[[target.org::#myid]]\n[[target.org::find this]]\n* Other\n")
  execute 'edit' path
  normal! zR
  org.FollowLink('*Other')
  Check('heading in this file', line('.'), 5)
  org.FollowLink('file:target.org::*Wanted')
  Check('other file', expand('%:t'), 'target.org')
  Check('heading there', line('.'), 2)
  org.FollowLink('#myid')
  Check('custom id', line('.'), 2)
  org.FollowLink('target.org::find this')
  Check('text search', line('.'), 6)
  Reset()
  execute 'edit' path
  normal! zR
  cursor(1, 12)
  execute 'OrgEnter'
  Check('enter follows', line('.'), 5)
  Reset()
enddef
TestLinks()

# --- agenda highlighting -----------------------------------------------------
def AgendaSyntaxAt(line: number, word: string, from = 1): string
  var column = stridx(getline(line), word, from - 1) + 1
  return synIDattr(synID(line, column, 1), 'name')
enddef

def TestAgendaSyntax()
  Reset()
  syntax enable
  enew
  setlocal buftype=nofile
  setline(1, [
    'Header',
    '  all:        TODO make items have TODO status and WAIT for DONE',
    '  all:        Check the TODO list',
    '  all:        TODOS for later',
    '  work:        8:00...... Scheduled:  IN PROGRESS Task',
    '  work:       In   3 d.:  WAIT Task',
    '  work:        2 d. ago:  DONE Task',
  ])
  set filetype=orgagenda
  Check('the real keyword is coloured', AgendaSyntaxAt(2, 'TODO'), 'orgAgendaTodo')
  Check('the same word in the title is not', AgendaSyntaxAt(2, 'TODO status'), 'orgAgendaItem')
  Check('nor another keyword', AgendaSyntaxAt(2, 'WAIT'), 'orgAgendaItem')
  Check('nor a done keyword', AgendaSyntaxAt(2, 'DONE'), 'orgAgendaItem')
  Check('no keyword, no colour', AgendaSyntaxAt(3, 'TODO'), 'orgAgendaItem')
  Check('a longer word is not a keyword', AgendaSyntaxAt(4, 'TODOS'), 'orgAgendaItem')
  Check('found after a time and leader', AgendaSyntaxAt(5, 'IN PROGRESS'), 'orgAgendaActive')
  Check('found after In N d.', AgendaSyntaxAt(6, 'WAIT'), 'orgAgendaWait')
  Check('found after N d. ago', AgendaSyntaxAt(7, 'DONE'), 'orgAgendaDone')
  syntax off
  Reset()
enddef
TestAgendaSyntax()

# --- agenda and capture, through real files ----------------------------------
def TestAgendaFlow()
  Reset()
  var dir = work .. '/flow'
  var todo = Fresh('flow/todo.org', "#+FILETAGS: :work:\n* Todo list\n** TODO Existing\n* After\n")
  Fresh('flow/.hidden.org', "* TODO Hidden\n")
  Fresh('flow/notes.txt', "* TODO Not org\n")
  g:orgflow = {
    'agenda.files': [dir],
    'agenda.width': 60,
    'capture.templates': [
      {key: 'w', description: 'Work'},
      {key: 'wt', description: 'Today', file: todo, headline: 'Todo list', prepend: true, schedule: '+0d'},
      {key: 'n', description: 'New file', file: dir .. '/made/up.org', headline: 'Inbox'},
    ],
  }
  Check('dotfiles and other files are skipped', agendaview.CollectPaths([dir]), [todo])
  Check('paths de-duplicate', agendaview.CollectPaths([dir, todo]), [todo])

  execute 'OrgAgenda c'
  Check('agenda filetype', &filetype, 'orgagenda')
  Check('read-only', &modifiable, false)
  Check('buffer is not a file', &buftype, 'nofile')
  var FindLine = (text: string): number => match(getline(1, '$'), text) + 1
  Check('shows the item', FindLine('TODO Existing') > 0, true)
  cursor(FindLine('TODO Existing'), 1)
  var target = agendaview.TargetAtCursor()
  Check('target', [target.path, target.line, target.raw], [todo, 2, '** TODO Existing'])

  # Marking an item from the agenda reaches the file.
  execute 'OrgTodo IN PROGRESS'
  Check('agenda edit reaches disk', Raw(todo), "#+FILETAGS: :work:\n* Todo list\n** IN PROGRESS Existing\n* After\n")
  Check('agenda refreshed', FindLine('IN PROGRESS Existing') > 0, true)

  # A file that changed behind the agenda is refused, not overwritten.
  writefile(['#+FILETAGS: :work:', '* Todo list', '** TODO Changed', '* After', ''], todo, 'b')
  cursor(FindLine('IN PROGRESS Existing'), 1)
  silent! execute 'OrgTodo DONE'
  Check('stale edit refused', Raw(todo), "#+FILETAGS: :work:\n* Todo list\n** TODO Changed\n* After\n")
  Check('and agenda catches up', FindLine('TODO Changed') > 0, true)

  # Capture, with a schedule, then see it on the week agenda.
  capture.CaptureTo(filter(copy(g:orgflow['capture.templates']), (_, t) => t.key ==# 'wt')[0], 'Captured thing')
  Check('capture wrote', Raw(todo), "#+FILETAGS: :work:\n* Todo list\n** TODO Captured thing \n SCHEDULED: <2026-11-11 Wed>\n** TODO Changed\n* After\n")
  capture.CaptureTo(filter(copy(g:orgflow['capture.templates']), (_, t) => t.key ==# 'n')[0], 'First')
  Check('capture makes a file', Raw(dir .. '/made/up.org'), "* Inbox\n** TODO First\n")

  # Capture into a file with unsaved work stays in the buffer.
  Reset()
  execute 'edit' todo
  setline(1, '#+FILETAGS: :work:unsaved:')
  capture.CaptureTo(filter(copy(g:orgflow['capture.templates']), (_, t) => t.key ==# 'wt')[0], 'Into dirty')
  Check('capture into a dirty buffer', getline(3), '** TODO Into dirty ')
  Check('keeps unsaved work', getline(1), '#+FILETAGS: :work:unsaved:')
  Check('still modified', &modified, true)
  Check('disk unchanged', stridx(Raw(todo), 'Into dirty'), -1)
  set nomodified
  Reset()

  # The date keys, and week movement.
  Fresh('flow/todo.org', "* TODO Dated\nSCHEDULED: <2026-11-11 Wed>\n* TODO Plain\n")
  execute 'OrgAgenda c'
  var FindAt = (text: string): number => match(getline(1, '$'), text) + 1
  cursor(FindAt('Scheduled:  TODO Dated'), 1)
  agendaview.ShiftDate(1)
  Check('date later', Raw(todo), "* TODO Dated\nSCHEDULED: <2026-11-12 Thu>\n* TODO Plain\n")
  cursor(FindAt('Scheduled:  TODO Dated'), 1)
  agendaview.ShiftDate(-1)
  Check('date earlier', Raw(todo), "* TODO Dated\nSCHEDULED: <2026-11-11 Wed>\n* TODO Plain\n")
  Check('this week', FindAt('W46') > 0, true)
  agendaview.ShiftWeek(1)
  Check('next week', FindAt('W47') > 0, true)
  agendaview.ShiftWeek(-1)

  # Opening an item, and a stale hidden agenda catching up.
  cursor(FindAt('Scheduled:  TODO Dated'), 1)
  agendaview.OpenItem(false)
  Check('opens the file', expand('%:p'), todo)
  Check('on the heading', line('.'), 1)
  Check('with its fold open', foldclosed(1), -1)
  setline(1, '* DONE Dated')
  write
  execute 'OrgAgenda c'
  Check('agenda sees the save', FindAt('DONE Dated') > 0 || FindAt('TODO Dated') == 0, true)
  agendaview.Quit()
  Check('quit returns', expand('%:p'), todo)

  # Errors in a view show in the buffer rather than failing silently.
  g:orgflow['agenda.views'] = [{key: 'b', description: 'Bad', blocks: [{type: 'tags', match: '+=='}]}]
  execute 'OrgAgenda b'
  Check('bad view explains itself', getline(1) =~# '^Agenda view failed', true)
  unlet g:orgflow
  Reset()
enddef
TestAgendaFlow()

# --- journal ---------------------------------------------------------------
def TestJournal()
  Reset()
  var dir = work .. '/journal'
  mkdir(dir, 'p')
  g:orgflow = {'journal.directory': dir}
  g:orgflow_test_clock = {today: date.ToAbs(2026, 12, 1), minutes: 555}
  writefile(readfile(shared .. '/fixtures/journal/rollover/Nov-2026.org', 'b'), dir .. '/Nov-2026.org', 'b')
  writefile(['not a journal file'], dir .. '/notes.org')
  journalview.NewEntry()
  var expected = shared .. '/golden/expected/journal-rollover'
  Check('rollover new file', readfile(dir .. '/Dec-2026.org', 'b'), readfile(expected .. '/Dec-2026.org', 'b'))
  Check('rollover old file', readfile(dir .. '/Nov-2026.org', 'b'), readfile(expected .. '/Nov-2026.org', 'b'))
  Check('opens the new file', expand('%:t'), 'Dec-2026.org')
  Check('on the new entry', getline('.'), '** 09:15 ')
  Check('with the cursor at its end', col('.'), strlen(getline('.')))
  Check('fold open', foldclosed('.'), -1)
  unlet g:orgflow
  g:orgflow_test_clock = {today: date.ToAbs(2026, 11, 11), minutes: 630}
  Reset()
enddef
TestJournal()

# --- projects --------------------------------------------------------------
def TestProjects()
  Reset()
  var root = work .. '/projects'
  for dir in ['alpha/.git', 'group/beta/.git', 'group/deep/a/b/c/d/.git', 'plain/sub', 'node_modules/nope/.git', '.hidden/x/.git']
    mkdir(root .. '/' .. dir, 'p')
  endfor
  writefile(['gitdir: elsewhere'], root .. '/group/.git-file')
  Check('recursive', projects.DiscoverProjects([{path: root, recursive: true}]), [root .. '/alpha', root .. '/group/beta'])
  Check('not recursive', projects.DiscoverProjects([root]), [root .. '/alpha'])
  Check('sorted by use', projects.SortProjects(['/a', '/b', '/c'], ['/c', '/gone', '/b']), ['/c', '/b', '/a'])
  projects.Remember('/one')
  projects.Remember('/two')
  projects.Remember('/one')
  Check('remembered', json_decode(join(readfile($XDG_STATE_HOME .. '/orgflow/vim-projects.json'), '')), ['/one', '/two'])
  # Inside a nested directory of a project, the root is the repository.
  mkdir(root .. '/alpha/src/x', 'p')
  execute 'edit' root .. '/alpha/src/x/file.txt'
  Check('project root', projects.ProjectRoot(), root .. '/alpha')
  Reset()
enddef
TestProjects()

# --- menus -----------------------------------------------------------------
def TestMenus()
  var tree = [
    {key: 'a', name: 'always', cmd: 'x'},
    {key: 'o', name: 'org only', cmd: 'y', filetypes: ['org']},
    {key: 'g', name: 'group', children: [{key: 'o', name: 'org', cmd: 'z', filetypes: ['org']}]},
  ]
  Check('filter org', len(menu.FilterTree(tree, 'org')), 3)
  Check('filter drops empty groups', mapnew(menu.FilterTree(tree, 'vim'), (_, n) => n.key), ['a'])
  var templates: list<dict<any>> = [
    {key: 't', description: 'Todo', file: 'x'},
    {key: 'w', description: 'Work'},
    {key: 'wt', description: 'Today', file: 'y'},
  ]
  var built = menu.TreeFromKeys(templates, (t) => has_key(t, 'file'))
  Check('leaf', built[0].value.key, 't')
  Check('group', built[1].name, 'Work')
  Check('child', built[1].children[0].value.key, 'wt')
enddef
TestMenus()

# Compiling every function catches type errors in paths the tests don't reach.
def CompileAll()
  for name in ['agenda', 'agendaview', 'capture', 'config', 'date', 'edits', 'files', 'fold', 'journal', 'journalview', 'match', 'menu', 'org', 'parser', 'picker', 'projects', 'table', 'timestamp']
    execute 'runtime autoload/orgflow/' .. name .. '.vim'
  endfor
  var compiled = 0
  for line in split(execute('function /\(orgflow#\|<SNR>\)'), "\n")
    var name = matchstr(line, '^def \zs[^(]\+')
    if name ==# '' || name =~# '<lambda>'
      continue
    endif
    try
      silent execute 'disassemble' name
      compiled += 1
    catch
      add(failures, 'FAIL compile ' .. name .. ': ' .. v:exception)
    endtry
  endfor
  Check('compiled many functions: ' .. compiled, compiled > 100, true)
enddef
CompileAll()

var out = failures + [printf('%d passed, %d failed', passed, len(failures))]
writefile(out, g:orgflow_result)
if empty(failures)
  writefile(['ok'], g:orgflow_result .. '.ok')
endif
