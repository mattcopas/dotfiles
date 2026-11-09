vim9script
# The org engine against real org-mode output, using the same fixtures and expected
# files as the VS Code extension, plus the edge cases from its unit tests.
# Run through test/run.sh. Clock: Wed 11 Nov 2026 10:30.
#
# ignorecase is on deliberately: match() and substitute() obey it, your .vimrc sets it,
# and a missed \C would otherwise only break things in real use.
set ignorecase smartcase

import autoload 'orgflow/agenda.vim'
import autoload 'orgflow/date.vim'
import autoload 'orgflow/edits.vim'
import autoload 'orgflow/journal.vim'
import autoload 'orgflow/match.vim' as matcher
import autoload 'orgflow/parser.vim'
import autoload 'orgflow/table.vim'
import autoload 'orgflow/timestamp.vim' as ts

const shared = g:orgflow_shared_tests
const fixtures = shared .. '/fixtures'
const expected = shared .. '/golden/expected'
const defaults: dict<any> = json_decode(join(readfile(g:orgflow_root .. '/defaults.json'), "\n"))
const config = parser.MakeConfig(defaults.todoKeywords)
const clock: dict<number> = {today: date.ToAbs(2026, 11, 11), minutes: 630}

var passed = 0
var failures: list<string> = []

def Check(name: string, got: any, want: any)
  if type(got) == type(want) && got == want
    passed += 1
    return
  endif
  add(failures, printf("FAIL %s\n  got:  %s\n  want: %s", name, string(got), string(want)))
enddef

def CheckThrows(name: string, Fn: func)
  try
    Fn()
    add(failures, 'FAIL ' .. name .. ': expected an error')
  catch
    passed += 1
  endtry
enddef

# Reads as split on newlines, so a final newline shows as a final empty element.
def Read(path: string): list<string>
  return readfile(path, 'b')
enddef

def Lines(text: string): list<string>
  return split(text, "\n", 1)
enddef

def CheckLines(name: string, got: list<string>, want: list<string>)
  if got == want
    passed += 1
    return
  endif
  var at = 0
  while at < len(got) && at < len(want) && got[at] ==# want[at]
    at += 1
  endwhile
  add(failures, printf("FAIL %s (first difference at line %d of %d/%d)\n  got:  %s\n  want: %s",
    name, at + 1, len(got), len(want), get(got, at, '<end>'), get(want, at, '<end>')))
enddef

def AgendaFiles(): list<dict<any>>
  var files: list<dict<any>> = []
  for dir in ['personal', 'client', 'work']
    var full = fixtures .. '/agenda/' .. dir
    for name in sort(readdir(full))
      var path = full .. '/' .. name
      if !isdirectory(path) && name =~# '^[^.].*\.org$'
        add(files, {path: path, base: fnamemodify(name, ':r'), lines: Read(path)})
      endif
    endfor
  endfor
  return files
enddef

def StripTrailingEmpty(lines: list<string>): list<string>
  var out = copy(lines)
  while !empty(out) && out[-1] ==# ''
    remove(out, -1)
  endwhile
  return out
enddef

# --- agenda ---------------------------------------------------------------
for view in defaults['agenda.views']
  var rendered = agenda.RenderView(view, AgendaFiles(), {config: config, clock: clock, width: 80})
  CheckLines('agenda ' .. view.key, mapnew(rendered, (_, l) => l.text),
    StripTrailingEmpty(Read(expected .. '/agenda-' .. view.key .. '.txt')))
endfor

def TestTargets()
  var rendered = agenda.RenderView(defaults['agenda.views'][0], AgendaFiles(), {config: config, clock: clock, width: 80})
  var items = filter(copy(rendered), (_, l) => has_key(l, 'target'))
  Check('agenda has items', len(items) > 20, true)
  var ok = true
  for item in items
    var source = Read(item.target.path)[item.target.line]
    ok = ok && source ==# item.target.raw && source =~# '^\*\+ '
  endfor
  Check('agenda targets point at headings', ok, true)
enddef
TestTargets()

# --- repeaters and scheduling ---------------------------------------------
def TestEdits()
  var lines = Read(fixtures .. '/edits/repeat.org')
  for heading in reverse(copy(parser.ParseOrg(lines, config).headings))
    lines = edits.SetTodo(lines, heading.line, 'DONE', config, clock)
  endfor
  CheckLines('repeaters', lines, Read(expected .. '/edit-repeat.org'))

  for [name, days] in [['today', 0], ['tomorrow', 1]]
    var scheduled = Read(fixtures .. '/edits/schedule.org')
    for heading in reverse(copy(parser.ParseOrg(scheduled, config).headings))
      scheduled = edits.SetPlanning(scheduled, heading.line, 'SCHEDULED', clock.today + days, -1, config)
    endfor
    CheckLines('schedule ' .. name, scheduled, Read(expected .. '/edit-schedule-' .. name .. '.org'))
  endfor
  CheckLines('rescheduling keeps a repeater',
    edits.SetPlanning(Lines("* TODO x\nSCHEDULED: <2026-01-01 Thu +1w>\n"), 0, 'SCHEDULED', clock.today, -1, config),
    Lines("* TODO x\nSCHEDULED: <2026-11-11 Wed +1w>\n"))
enddef
TestEdits()

# --- structure ------------------------------------------------------------
def TestStructure()
  var source = Read(fixtures .. '/edits/structure.org')
  var At = (title: string): number => filter(copy(parser.ParseOrg(source, config).headings), (_, h) => h.title ==# title)[0].line
  var cases: list<list<any>> = [
    ['edit-move-down.org', edits.MoveSubtree(source, At('First'), 'down', config).lines],
    ['edit-move-second-up.org', edits.MoveSubtree(source, At('Second'), 'up', config).lines],
    ['edit-move-child-down.org', edits.MoveSubtree(source, At('First child'), 'down', config).lines],
    ['edit-move-up.org', edits.MoveSubtree(source, At('Second child'), 'up', config).lines],
    ['edit-promote.org', edits.ShiftHeading(source, At('First child'), -1, config)],
    ['edit-promote-subtree.org', edits.ShiftSubtree(source, At('First child'), -1, config)],
    ['edit-demote.org', edits.ShiftHeading(source, At('First'), 1, config)],
    ['edit-demote-subtree.org', edits.ShiftSubtree(source, At('Second child'), 1, config)],
    ['edit-demote-third.org', edits.ShiftHeading(source, At('Third'), 1, config)],
  ]
  for [file, got] in cases
    CheckLines(file, got, Read(expected .. '/' .. file))
  endfor
  CheckThrows('subtree stops at its parent', () => edits.MoveSubtree(source, At('Second child'), 'down', config))
  CheckThrows('first subtree stops at the top', () => edits.MoveSubtree(source, At('First'), 'up', config))
  CheckThrows('level 1 can''t promote', () => edits.ShiftHeading(source, At('First'), -1, config))
enddef
TestStructure()

# --- capture --------------------------------------------------------------
def TestCapture()
  var base = Lines("#+TITLE: Capture\n\n* Before\n* Todo list\nIntro line.\n** TODO Existing one\n** TODO Existing two\nBody.\n* After\n")
  var Stamp = (title: string, days: number): dict<any> => ({
    headline: 'Todo list',
    prepend: true,
    entry: 'TODO ' .. title .. ' ',
    extraLines: [' SCHEDULED: ' .. ts.FormatStamp(clock.today + days, -1)],
  })
  var cases: list<list<any>> = [
    ['ww', {headline: 'Todo list', prepend: true, entry: 'TODO Work plain'}, base],
    ['wt', Stamp('Work today', 0), base],
    ['wT', Stamp('Work tomorrow', 1), base],
    ['t', {headline: 'Todo list', prepend: false, entry: 'TODO Plain append'}, base],
    ['new', {headline: 'Todo list', prepend: true, entry: 'TODO Into new headline'}, Lines("* Other\n")],
  ]
  for [name, spec, input] in cases
    CheckLines('capture ' .. name, edits.CaptureEntry(input, spec, config).lines, Read(expected .. '/edit-capture-' .. name .. '.org'))
  endfor
  CheckLines('capture into an empty file',
    edits.CaptureEntry([''], {headline: 'Todo list', prepend: true, entry: 'TODO x'}, config).lines,
    Lines("* Todo list\n** TODO x\n"))
  var placed = edits.CaptureEntry(base, {headline: 'Todo list', prepend: true, entry: 'TODO y'}, config)
  Check('capture reports its line', placed.lines[placed.line], '** TODO y')
enddef
TestCapture()

# --- tables ---------------------------------------------------------------
def TestTables()
  var lines = Read(fixtures .. '/edits/table.org')
  lines = table.AlignTableAt(lines, 1)
  lines = table.AlignTableAt(lines, match(lines, '^|a|'))
  CheckLines('table align', lines, Read(expected .. '/edit-table-align.org'))
  var once = table.AlignTableAt(Lines("| a | bb |\n|--\n| ccc | 1 |\n"), 0)
  Check('align is idempotent', table.AlignTableAt(once, 0), once)
  var grid = ['| a | b |', '|---+---|', '| c | d |', 'after']
  Check('next cell on a row', table.NextCell(grid, 0, 2), {line: 0, column: 6, addRow: false})
  Check('next cell skips a rule', table.NextCell(grid, 0, 6), {line: 2, column: 2, addRow: false})
  Check('next cell at the end', table.NextCell(grid, 2, 6), {line: 3, column: 0, addRow: true})
  Check('blank row', table.BlankRow('| ab | c |'), '|    |   |')
  Check('wide characters align', table.AlignTableAt(['|日本|', '|abc|'], 0), ['| 日本 |', '| abc  |'])
enddef
TestTables()

# --- journal --------------------------------------------------------------
def TestJournal()
  var jc: dict<any> = {
    fileFormat: defaults['journal.fileFormat'],
    dateFormat: defaults['journal.dateFormat'],
    carryover: defaults['journal.carryover'],
  }
  var At = (y: number, m: number, d: number, hh: number, mm: number): dict<number> => ({today: date.ToAbs(y, m, d), minutes: hh * 60 + mm})
  var Fixture = (name: string): list<string> => Read(fixtures .. '/journal/' .. name .. '/Nov-2026.org')
  var Want = (name: string, file: string): list<string> => Read(expected .. '/journal-' .. name .. '/' .. file)
  var Plan = (when: dict<number>, current: list<string>): dict<any> => journal.PlanNewEntry({clock: when, config: jc, orgConfig: config, currentLines: current})
  var now = At(2026, 11, 11, 14, 32)

  CheckLines('journal new file', Plan(now, ['']).current, Want('empty', 'Nov-2026.org'))
  CheckLines('journal single digit', Plan(At(2027, 3, 2, 9, 5), ['']).current, Want('single-digit', 'Mar-2027.org'))
  CheckLines('journal in month', Plan(now, Fixture('inmonth')).current, Want('inmonth', 'Nov-2026.org'))

  # org-journal leaves one stray blank line when the item it deletes sits directly above
  # today's heading. That's a side effect, so neither port copies it.
  var nestedWant = Want('nested', 'Nov-2026.org')
  var blank = match(nestedWant, '^\* Wed') - 1
  Check('nested fixture still has the stray blank', nestedWant[blank], '')
  remove(nestedWant, blank)
  var nested = Plan(now, Fixture('nested'))
  CheckLines('journal nested', nested.current, nestedWant)
  Check('entry line points at the entry', nested.current[nested.line], '** 14:32 ')

  var rollover = journal.PlanNewEntry({
    clock: At(2026, 12, 1, 9, 15),
    config: jc,
    orgConfig: config,
    currentLines: [''],
    previousLines: Fixture('rollover'),
  })
  CheckLines('journal rollover new month', rollover.current, Want('rollover', 'Dec-2026.org'))
  CheckLines('journal rollover old month', rollover.previous, Want('rollover', 'Nov-2026.org'))

  CheckLines('journal same day', Plan(now, Fixture('sameday')).current, Want('sameday', 'Nov-2026.org'))
  CheckLines('journal twice', Plan(now, Plan(now, Fixture('inmonth')).current).current, Want('twice', 'Nov-2026.org'))

  var names: dict<any> = {fileFormat: '%b-%Y.org', dateFormat: '%a %e %b %Y', carryover: ''}
  Check('journal name', journal.JournalFileName(date.ToAbs(2026, 11, 8), names), 'Nov-2026.org')
  Check('name to month', journal.FileNameToMonth('Nov-2026.org', names), date.ToAbs(2026, 11, 1))
  Check('other name', journal.FileNameToMonth('notes.org', names), -1)
  Check('bad month', journal.FileNameToMonth('Xyz-2026.org', names), -1)
  var days = Lines("* a\n:PROPERTIES:\n:CREATED:  20261103\n:END:\n* b\n:PROPERTIES:\n:CREATED:  20261120\n:END:\n")
  Check('latest earlier day', journal.LatestDayBefore(days, date.ToAbs(2026, 11, 11), config), date.ToAbs(2026, 11, 3))
  Check('no earlier day', journal.LatestDayBefore(days, date.ToAbs(2026, 11, 1), config), -1)
enddef
TestJournal()

# --- dates ----------------------------------------------------------------
def TestDates()
  for [y, m, d] in [[2024, 2, 29], [1970, 1, 1], [2000, 3, 1], [2026, 12, 31]]
    Check('round trip', date.FromAbs(date.ToAbs(y, m, d)), {y: y, m: m, d: d})
  endfor
  Check('weekday', date.Weekday(date.ToAbs(2026, 11, 11)), 3)
  Check('iso week', date.IsoWeek(date.ToAbs(2026, 11, 11)), 46)
  Check('iso week 53', date.IsoWeek(date.ToAbs(2027, 1, 1)), 53)
  Check('iso week 1', date.IsoWeek(date.ToAbs(2024, 12, 30)), 1)
  Check('months clamp', date.FromAbs(date.AddMonths(date.ToAbs(2026, 1, 31), 1)), {y: 2026, m: 2, d: 28})
  Check('months wrap', date.FromAbs(date.AddMonths(date.ToAbs(2026, 12, 15), 1)), {y: 2027, m: 1, d: 15})
  Check('months back', date.FromAbs(date.AddMonths(date.ToAbs(2026, 1, 15), -1)), {y: 2025, m: 12, d: 15})
  Check('%e pads', date.FormatDate('%a %e %b %Y', date.ToAbs(2026, 11, 8)), 'Sun  8 Nov 2026')
  Check('%H:%M', date.FormatDate('%H:%M', date.ToAbs(2026, 11, 8), 65), '01:05')
enddef
TestDates()

# --- timestamps -----------------------------------------------------------
def TestStamps()
  var stamp = ts.ParseTimestamp('<2026-11-11 Wed 09:30-10:15 ++1w -3d>')
  Check('stamp abs', stamp.abs, date.ToAbs(2026, 11, 11))
  Check('stamp start', stamp.minutes, 570)
  Check('stamp end', stamp.endMinutes, 615)
  Check('stamp repeater', stamp.repeater, {type: '++', n: 1, unit: 'w'})
  Check('stamp warning', stamp.warning, {once: false, n: 3, unit: 'd'})
  Check('no weekday', ts.ParseTimestamp('<2026-11-11>').abs, date.ToAbs(2026, 11, 11))
  Check('inactive', ts.ParseTimestamp('[2026-11-11 Wed]').active, false)
  Check('mismatched brackets', ts.ParseTimestamp('<2026-11-11 Wed]'), {})
  Check('range', mapnew(ts.FindTimestamps('<2026-11-11 Wed>--<2026-11-13 Fri>'), (_, s) => s.inRange), [true, true])
  var weekly = ts.ParseTimestamp('<2026-11-02 Mon +1w>')
  Check('next', ts.NextOccurrence(weekly, date.ToAbs(2026, 11, 10)), date.ToAbs(2026, 11, 16))
  Check('next exact', ts.NextOccurrence(weekly, date.ToAbs(2026, 11, 9)), date.ToAbs(2026, 11, 9))
  Check('previous', ts.PreviousOccurrence(weekly, date.ToAbs(2026, 11, 10)), date.ToAbs(2026, 11, 9))
  Check('before base', ts.NextOccurrence(weekly, date.ToAbs(2026, 1, 1)), weekly.abs)
  Check('monthly clamps', ts.NextOccurrence(ts.ParseTimestamp('<2026-01-31 Sat +1m>'), date.ToAbs(2026, 2, 10)), date.ToAbs(2026, 2, 28))
  Check('catch-up', ts.RepeatedDate(ts.ParseTimestamp('<2026-11-04 Wed ++1w>'), clock), date.ToAbs(2026, 11, 18))
  var today = clock.today
  var Abs = (text: string): number => ts.ParseDateInput(text, today).abs
  Check('+1d', Abs('+1d'), today + 1)
  Check('-2d', Abs('-2d'), today - 2)
  Check('+2w', Abs('+2w'), today + 14)
  Check('.', Abs('.'), today)
  Check('empty', Abs(''), today)
  Check('tomorrow', Abs('tomorrow'), today + 1)
  Check('fri', Abs('fri'), today + 2)
  Check('mon', Abs('mon'), today + 5)
  Check('wed', Abs('wed'), today)
  Check('iso', Abs('2027-01-02'), date.ToAbs(2027, 1, 2))
  Check('12-25', Abs('12-25'), date.ToAbs(2026, 12, 25))
  Check('01-02', Abs('01-02'), date.ToAbs(2027, 1, 2))
  Check('20', Abs('20'), date.ToAbs(2026, 11, 20))
  Check('3', Abs('3'), date.ToAbs(2026, 12, 3))
  Check('time', ts.ParseDateInput('+1d 14:30', today).minutes, 870)
  Check('nonsense', ts.ParseDateInput('nonsense', today), {})
enddef
TestStamps()

# --- parser ---------------------------------------------------------------
def TestParser()
  var doc = parser.ParseOrg([
    '#+FILETAGS: :top:',
    '#+CATEGORY: cat',
    '* IN PROGRESS [#A] Multi word :one:two:',
    'SCHEDULED: <2026-11-11 Wed> DEADLINE: <2026-11-12 Thu>',
    ':PROPERTIES:',
    ':OWNER: me',
    ':CATEGORY: own',
    ':END:',
    '** INPROGRESS not a keyword',
    '** [ ] checkbox state',
    '** [X] done checkbox',
    '*bold* is not a heading',
    '* :onlytag:',
    '* ',
  ], config, 'file')
  var [first, notKeyword, checkbox, done, onlyTag, none] = doc.headings
  Check('keyword with a space', first.keyword, 'IN PROGRESS')
  Check('priority', first.priority, 'A')
  Check('title', first.title, 'Multi word')
  Check('tags', first.localTags, ['one', 'two'])
  Check('filetags', first.inheritedTags, ['top'])
  Check('word boundary', notKeyword.keyword, '')
  Check('title without keyword', notKeyword.title, 'INPROGRESS not a keyword')
  Check('bracket keyword', checkbox.keyword, '[ ]')
  Check('done bracket', done.keyword, '[X]')
  Check('scheduled', first.scheduled.abs, date.ToAbs(2026, 11, 11))
  Check('deadline', first.deadline.abs, date.ToAbs(2026, 11, 12))
  Check('property', first.properties.OWNER, 'me')
  Check('inherited', notKeyword.inheritedTags, ['top', 'one', 'two'])
  Check('own category', first.category, 'own')
  Check('inherited category', notKeyword.category, 'own')
  Check('file category', onlyTag.category, 'cat')
  Check('count', len(doc.headings), 6)
  Check('subtree end', first.subtreeEnd, onlyTag.line)
  Check('entry end', first.entryEnd, notKeyword.line)
  Check('*bold* stays in the entry', done.entryEnd, onlyTag.line)
  Check('only tag', onlyTag.localTags, ['onlytag'])
  Check('empty title', none.title, '')
  Check('before first heading', parser.HeadingAt(doc, 0), {})
  Check('heading at', parser.HeadingAt(doc, 4).line, first.line)
  Check('hotkey', config.keys['IN PROGRESS'], 'p')
  Check('no hotkey', has_key(config.keys, 'LOOP'), 0)
  Check('done-only sequence', has_key(config.doneWords, 'OKAY'), 1)
  Check('done word isn''t todo', has_key(config.todoWords, 'OKAY'), 0)
  Check('no bar', parser.MakeConfig([['A', 'B']]).sequences, [{todo: ['A'], done: ['B']}])
enddef
TestParser()

# --- match expressions ----------------------------------------------------
def TestMatch()
  var doc = parser.ParseOrg([
    '#+FILETAGS: :work:',
    '* TODO [#A] One :urgent:',
    'SCHEDULED: <2026-11-11 Wed>',
    ':PROPERTIES:',
    ':EFFORT: 5',
    ':END:',
    '* DONE Two',
    'SCHEDULED: <2026-11-11 Wed 09:00>',
    '* Three',
  ], config)
  var Hit = (expression: string, i: number, todoOnly: bool): bool => matcher.Matches(matcher.ParseMatch(expression, todoOnly), doc.headings[i], config, clock)
  for [expression, i, want] in [
      ['work', 0, true], ['+work+urgent', 0, true], ['+work-urgent', 0, false],
      ['work&urgent', 0, true], ['missing|urgent', 0, true], ['urgent', 1, false],
      ['TODO="TODO"', 0, true], ['PRIORITY="A"', 0, true], ['PRIORITY="B"', 2, true],
      ['LEVEL=1', 0, true], ['EFFORT>3', 0, true], ['EFFORT>9', 0, false],
      ['TODO<>"DONE"', 0, true], ['TODO={T.*}', 0, true],
      ['SCHEDULED="<today>"', 0, true], ['SCHEDULED="<today>"', 1, false],
      ['SCHEDULED<="<tomorrow>"', 1, true], ['SCHEDULED="<today>"', 2, false],
      ['SCHEDULED<>"<today>"', 2, true],
      ['work/DONE', 1, true], ['work/DONE', 0, false], ['work/!', 0, true], ['work/!', 1, false],
      ]
    Check('match ' .. expression, Hit(expression, i, false), want)
  endfor
  Check('todo only done', Hit('work', 1, true), false)
  Check('todo only todo', Hit('work', 0, true), true)
  Check('todo only none', Hit('work', 2, true), false)
  Check('match is case sensitive', Hit('WORK', 0, false), false)
  CheckThrows('bad match', () => matcher.ParseMatch('+work+=='))
enddef
TestMatch()

# --- edits ----------------------------------------------------------------
def TestSmallEdits()
  var Todo = (text: string, keyword: string): list<string> => edits.SetTodo(Lines(text), 0, keyword, config, clock)
  var body = "* TODO Title     :tag:\nBody\n"
  Check('keeps tag spacing', Todo(body, 'IN PROGRESS'), Lines("* IN PROGRESS Title     :tag:\nBody\n"))
  Check('clears', Todo(body, ''), Lines("* Title     :tag:\nBody\n"))
  Check('adds', Todo('* Title', 'TODO'), ['* TODO Title'])
  Check('bare', Todo('* TODO', 'DONE'), ['* DONE'])
  Check('multi word', Todo('* IN REVIEW x', 'TODO'), ['* TODO x'])
  var finished = "* DONE x\nSCHEDULED: <2026-11-04 Wed +1w>\n"
  Check('only leaving not-done repeats', Todo(finished, 'KILL'), Lines("* KILL x\nSCHEDULED: <2026-11-04 Wed +1w>\n"))
  Check('head of matching sequence', Todo("* [-] x\nSCHEDULED: <2026-11-04 Wed +1w>\n", '[X]'), Lines("* [ ] x\nSCHEDULED: <2026-11-11 Wed +1w>\n"))
  CheckThrows('non-heading refuses', () => edits.SetTodo(['text'], 0, 'TODO', config, clock))
  Check('deadline added', edits.SetPlanning(['* x', 'body'], 0, 'DEADLINE', clock.today, 870, config), ['* x', 'DEADLINE: <2026-11-11 Wed 14:30>', 'body'])
  Check('deadline ordered', edits.SetPlanning(['* x', 'SCHEDULED: <2026-01-01 Thu>'], 0, 'DEADLINE', clock.today, -1, config), ['* x', 'SCHEDULED: <2026-01-01 Thu> DEADLINE: <2026-11-11 Wed>'])
  Check('shift keeps the stamp', edits.ShiftPlanning(['* x', 'SCHEDULED: <2026-11-11 Wed 09:00 +1w>'], 0, 'SCHEDULED', 1, config), ['* x', 'SCHEDULED: <2026-11-12 Thu 09:00 +1w>'])
  Check('shift nothing', edits.ShiftPlanning(['* x'], 0, 'SCHEDULED', 1, config), [])
  var Step = (text: string, direction: string): list<string> => edits.ChangePriority([text], 0, direction, config)
  Check('priority default', Step('* TODO x', 'up'), ['* TODO [#B] x'])
  Check('priority up', Step('* TODO [#B] x', 'up'), ['* TODO [#A] x'])
  Check('priority off the top', Step('* TODO [#A] x', 'up'), ['* TODO x'])
  Check('priority down', Step('* TODO [#B] x', 'down'), ['* TODO [#C] x'])
  Check('priority off the bottom', Step('* TODO [#C] x', 'down'), ['* TODO x'])
  Check('priority keeps tags', Step('* x :tag:', 'down'), ['* [#B] x :tag:'])
  Check('tags set', edits.SetTags(['* x'], 0, ['a', 'b'], config), ['* x :a:b:'])
  Check('tags replaced', edits.SetTags(['* x    :old:'], 0, ['new'], config), ['* x :new:'])
  Check('tags cleared', edits.SetTags(['* x :old:'], 0, [], config), ['* x'])
  var moved = edits.MoveSubtree(Lines("* a\nbody\n* b\n"), 0, 'down', config)
  Check('last subtree keeps final newline', moved.lines, Lines("* b\n* a\nbody\n"))
  Check('moved line', moved.line, 1)
  Check('moved up', edits.MoveSubtree(Lines("* a\n* b\nbody\n"), 1, 'up', config).lines, Lines("* b\nbody\n* a\n"))
  var open = edits.MoveSubtree(Lines("* a\n* b\nbody"), 0, 'down', config)
  Check('no final newline', open.lines, Lines("* b\nbody\n* a"))
  Check('no final newline line', open.line, 2)
  var back = edits.MoveSubtree(open.lines, 2, 'up', config)
  Check('moves back', back.lines, Lines("* a\n* b\nbody"))
  Check('moves back line', back.line, 0)
enddef
TestSmallEdits()

# --- the expected files really came from the settings Vim reads -------------
def TestDefaultsMatchExtension()
  var manifest: dict<any> = json_decode(join(readfile(g:orgflow_root .. '/../../vscode/orgflow/package.json'), "\n"))
  var properties: dict<any> = manifest.contributes.configuration.properties
  for key in keys(defaults)
    Check('default ' .. key, defaults[key], properties['orgflow.' .. key].default)
  endfor
enddef
TestDefaultsMatchExtension()

const out = failures + [printf('%d passed, %d failed', passed, len(failures))]
writefile(out, g:orgflow_result)
if empty(failures)
  writefile(['ok'], g:orgflow_result .. '.ok')
endif
