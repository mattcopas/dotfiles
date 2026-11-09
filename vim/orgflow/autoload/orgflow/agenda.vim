vim9script
# The agenda engine. The behaviour and the layout both follow org-agenda, and the
# shared expected files under vscode/orgflow/test/golden hold the real org output.
#
# RenderView returns a list of {text, target}. A target ({path, line, raw, kind}) is
# only there for item lines. `line` counts from 0, and `raw` is the heading line when
# rendered, which detects that the file has moved on.
import './date.vim'
import './match.vim' as matcher
import './parser.vim'
import './timestamp.vim' as ts

def PriorityValue(heading: dict<any>, config: dict<any>): number
  var cookie: string = heading.priority !=# '' ? heading.priority : config.defaultPriority
  if cookie !~# '^[A-Z]$'
    return 0
  endif
  return 1000 * (char2nr('C') - char2nr(cookie))
enddef

# org shows tags as `:inherited::local:`, with the seam between the two groups.
def TagText(heading: dict<any>): string
  var inherited: list<string> = heading.inheritedTags
  var own: list<string> = heading.localTags
  if empty(inherited) && empty(own)
    return ''
  endif
  if empty(inherited)
    return ':' .. join(own, ':') .. ':'
  endif
  return ':' .. join(inherited, ':') .. ':' .. (empty(own) ? ':' : ':' .. join(own, ':') .. ':')
enddef

def ClockTime(minutes: number): string
  return printf('%2d:%02d', minutes / 60, minutes % 60)
enddef

def PadEnd(text: string, width: number): string
  return text .. repeat(' ', max([0, width - strwidth(text)]))
enddef

def FormatLine(item: dict<any>, options: dict<any>, withTime: bool): dict<any>
  var category = PadEnd(item.heading.category .. ':', 12)
  var time = ''
  if withTime && item.minutes >= 0
    var span = item.endMinutes >= 0
      ? ClockTime(item.minutes) .. '-' .. trim(ClockTime(item.endMinutes))
      : ClockTime(item.minutes) .. '......'
    time = span .. ' '
  endif
  var base = '  ' .. category .. time .. item.leader .. item.heading.text
  var tags = TagText(item.heading)
  var gap = max([1, options.width - 1 - strwidth(base) - strwidth(tags)])
  return {
    text: tags ==# '' ? base : base .. repeat(' ', gap) .. tags,
    target: {
      path: item.file.path,
      line: item.heading.line,
      raw: item.file.doc.lines[item.heading.line],
      kind: item.kind,
    },
  }
enddef

def WordsFor(value: any, config: dict<any>): dict<bool>
  if type(value) == v:t_list
    var words: dict<bool> = {}
    for word in value
      words[word] = true
    endfor
    return words
  endif
  if value ==# 'done'
    return config.doneWords
  elseif value ==# 'todo'
    return config.todoWords
  elseif value ==# 'any'
    var words: dict<bool> = {}
    for word in config.keywords
      words[word] = true
    endfor
    return words
  endif
  throw printf('Unknown TODO class "%s"', value)
enddef

def RuleApplies(rule: dict<any>, heading: dict<any>, options: dict<any>): bool
  var config: dict<any> = options.config
  var kind: string = rule.if
  if kind ==# 'todo' || kind ==# 'nottodo'
    var words = WordsFor(rule.value, config)
    var hit = heading.keyword !=# '' && has_key(words, heading.keyword)
    return kind ==# 'todo' ? hit : !hit
  elseif kind ==# 'priority'
    return (heading.priority !=# '' ? heading.priority : config.defaultPriority) ==# rule.value
  elseif kind ==# 'scheduled'
    return !empty(heading.scheduled)
  elseif kind ==# 'deadline'
    return !empty(heading.deadline)
  endif
  throw printf('Unknown skip rule "%s"', kind)
enddef

# The heading index to continue from when a skip rule fires, or -1 to keep it.
def SkipTo(block: dict<any>, heading: dict<any>, doc: dict<any>, options: dict<any>): number
  for rule in get(block, 'skip', [])
    if !RuleApplies(rule, heading, options)
      continue
    endif
    if get(rule, 'scope', 'entry') !=# 'subtree'
      return heading.index + 1
    endif
    var next = heading.index + 1
    while next < len(doc.headings) && doc.headings[next].level > heading.level
      next += 1
    endwhile
    return next
  endfor
  return -1
enddef

def SortByUrgency(items: list<dict<any>>): list<dict<any>>
  # sort() is stable, so equal items keep their order.
  return sort(copy(items), (a, b) => b.urgency - a.urgency)
enddef

def TagsBlock(block: dict<any>, files: list<dict<any>>, options: dict<any>): list<dict<any>>
  var parsedMatch = matcher.ParseMatch(get(block, 'match', ''), block.type ==# 'tags-todo')
  var items: list<dict<any>> = []
  for file in files
    var headings: list<dict<any>> = file.doc.headings
    var i = 0
    while i < len(headings)
      var heading = headings[i]
      if !matcher.Matches(parsedMatch, heading, options.config, options.clock)
        i += 1
        continue
      endif
      var skip = SkipTo(block, heading, file.doc, options)
      if skip >= 0
        i = skip
        continue
      endif
      add(items, {
        file: file,
        heading: heading,
        kind: 'tag',
        leader: '',
        urgency: PriorityValue(heading, options.config),
        minutes: -1,
        endMinutes: -1,
      })
      # org-tags-match-list-sublevels is nil: a match hides its whole subtree.
      var next = i + 1
      while next < len(headings) && headings[next].level > heading.level
        next += 1
      endwhile
      i = next
    endwhile
  endfor
  var header = has_key(block, 'header') ? block.header : 'Headlines with TAGS match: ' .. get(block, 'match', '')
  return [{text: header}] + mapnew(SortByUrgency(items), (_, item) => FormatLine(item, options, false))
enddef

def AllTodoBlock(block: dict<any>, files: list<dict<any>>, options: dict<any>): list<dict<any>>
  var items: list<dict<any>> = []
  for file in files
    var headings: list<dict<any>> = file.doc.headings
    var i = 0
    while i < len(headings)
      var heading = headings[i]
      if heading.keyword ==# '' || has_key(options.config.doneWords, heading.keyword)
        i += 1
        continue
      endif
      var skip = SkipTo(block, heading, file.doc, options)
      if skip >= 0
        i = skip
        continue
      endif
      add(items, {
        file: file,
        heading: heading,
        kind: 'todo',
        leader: '',
        urgency: PriorityValue(heading, options.config) + 1,
        minutes: -1,
        endMinutes: -1,
      })
      i += 1
    endwhile
  endfor
  var header = get(block, 'header', 'Global list of TODO items of type: ALL')
  return [{text: header}] + mapnew(SortByUrgency(items), (_, item) => FormatLine(item, options, false))
enddef

def IsDone(heading: dict<any>, options: dict<any>): bool
  return heading.keyword !=# '' && has_key(options.config.doneWords, heading.keyword)
enddef

# An item dict, or {} when this deadline doesn't show on this day.
def DeadlineItem(file: dict<any>, heading: dict<any>, stamp: dict<any>, current: number, options: dict<any>): dict<any>
  var today: number = options.clock.today
  var deadline: number = stamp.abs
  var rep = current <= today ? deadline : ts.NextOccurrence(stamp, current)
  var diff = deadline - current
  var isToday = current == today
  if current != deadline && current != rep
    if !isToday
      return {}
    endif
    if deadline > current && diff > ts.WarningDays(stamp, get(options, 'deadlineWarningDays', 14))
      return {}
    endif
  endif
  if IsDone(heading, options) && deadline != current
    return {}
  endif
  var leader = ''
  if current == deadline || current == rep
    leader = 'Deadline:   '
  elseif deadline > current
    leader = printf('In %3d d.:  ', diff)
  else
    leader = printf('%2d d. ago:  ', -diff)
  endif
  var reminder = current != deadline && current != rep
  return {
    file: file,
    heading: heading,
    kind: 'deadline',
    leader: leader,
    urgency: PriorityValue(heading, options.config) + (isToday ? -diff : 0),
    minutes: reminder ? -1 : stamp.minutes,
    endMinutes: reminder ? -1 : stamp.endMinutes,
  }
enddef

def ScheduledItem(file: dict<any>, heading: dict<any>, stamp: dict<any>, current: number, options: dict<any>): dict<any>
  var today: number = options.clock.today
  var schedule: number = stamp.abs
  var rep = current <= today ? schedule : ts.NextOccurrence(stamp, current)
  var diff = current - schedule
  var delay = empty(stamp.warning) ? 0 : ts.WarningDays(stamp, 0)
  if (delay > 0 && diff < delay) || schedule > current || (current != schedule && current != today && current != rep)
    return {}
  endif
  if IsDone(heading, options) && schedule != current
    return {}
  endif
  var isBase = current == schedule || current == rep
  var leader = current == today && schedule < today ? printf('Sched.%2dx:  ', diff) : 'Scheduled:  '
  return {
    file: file,
    heading: heading,
    kind: 'scheduled',
    leader: leader,
    urgency: 99 + diff + PriorityValue(heading, options.config),
    minutes: isBase ? stamp.minutes : -1,
    endMinutes: isBase ? stamp.endMinutes : -1,
  }
enddef

def PlainStampItems(file: dict<any>, heading: dict<any>, current: number, options: dict<any>): list<dict<any>>
  var today: number = options.clock.today
  var items: list<dict<any>> = []
  var lines: list<string> = file.doc.lines
  var at: number = heading.line
  while at < heading.entryEnd
    var line = lines[at]
    at += 1
    if parser.IsPlanningLine(line)
      continue
    endif
    for stamp in ts.FindTimestamps(line)
      if !stamp.active || stamp.inRange
        continue
      endif
      var past = ts.PreviousOccurrence(stamp, current > today ? today : current)
      var future = current <= today ? past : ts.NextOccurrence(stamp, current)
      if current < stamp.abs || (current != past && current != future)
        continue
      endif
      add(items, {
        file: file,
        heading: heading,
        kind: 'timestamp',
        leader: '',
        urgency: PriorityValue(heading, options.config),
        minutes: stamp.minutes,
        endMinutes: stamp.endMinutes,
      })
    endfor
  endwhile
  return items
enddef

const GRID_TIMES: list<number> = [480, 600, 720, 840, 960, 1080, 1200]
const NOW_LINE = 'now - - - - - - - - - - - - - - - - - - - - - - - - -'
const GRID_LINE = '----------------'

def GridLine(minutes: number, text: string): dict<any>
  return {text: '  ' .. repeat(' ', 12) .. ClockTime(minutes) .. '...... ' .. text}
enddef

def DayEntries(current: number, files: list<dict<any>>, block: dict<any>, options: dict<any>): list<dict<any>>
  var items: list<dict<any>> = []
  var hasSkip = !empty(get(block, 'skip', []))
  for file in files
    var deadlines: list<dict<any>> = []
    var scheduled: list<dict<any>> = []
    var stamps: list<dict<any>> = []
    for heading in file.doc.headings
      if hasSkip && SkipTo(block, heading, file.doc, options) >= 0
        continue
      endif
      if !empty(heading.deadline) && heading.deadline.active
        var item = DeadlineItem(file, heading, heading.deadline, current, options)
        if !empty(item)
          add(deadlines, item)
        endif
      endif
      if !empty(heading.scheduled) && heading.scheduled.active
        var item = ScheduledItem(file, heading, heading.scheduled, current, options)
        if !empty(item)
          add(scheduled, item)
        endif
      endif
      stamps += PlainStampItems(file, heading, current, options)
    endfor
    items += deadlines + scheduled + stamps
  endfor

  var timed = sort(filter(copy(items), (_, item) => item.minutes >= 0),
    (a, b) => a.minutes != b.minutes ? a.minutes - b.minutes : b.urgency - a.urgency)
  var untimed = SortByUrgency(filter(copy(items), (_, item) => item.minutes < 0))

  var timedLines: list<dict<any>> = mapnew(timed, (_, item) => ({
    minutes: item.minutes,
    rank: 1,
    line: FormatLine(item, options, true),
  }))

  # org only draws the time grid on today, and only when something has a time.
  if current == options.clock.today && !empty(timed)
    var taken = mapnew(timed, (_, item) => item.minutes)
    for minutes in GRID_TIMES
      if index(taken, minutes) < 0
        add(timedLines, {minutes: minutes, rank: 0, line: GridLine(minutes, GRID_LINE)})
      endif
    endfor
    add(timedLines, {minutes: options.clock.minutes, rank: 2, line: GridLine(options.clock.minutes, NOW_LINE)})
  endif
  sort(timedLines, (a, b) => a.minutes != b.minutes ? a.minutes - b.minutes : a.rank - b.rank)

  return mapnew(timedLines, (_, entry) => entry.line)
    + mapnew(untimed, (_, item) => FormatLine(item, options, false))
enddef

def DayHeader(abs: number): string
  var c = date.FromAbs(abs)
  var base = printf('%-10s %2d %s %4d', date.DAY_LONG[date.Weekday(abs)], c.d, date.MONTH_LONG[c.m - 1], c.y)
  return date.Weekday(abs) == 1 ? printf('%s W%02d', base, date.IsoWeek(abs)) : base
enddef

def AgendaBlock(block: dict<any>, files: list<dict<any>>, options: dict<any>): list<dict<any>>
  var today: number = options.clock.today
  var monday = today - ((date.Weekday(today) + 6) % 7) + get(options, 'weekOffset', 0) * 7
  var header = has_key(block, 'header') ? block.header : printf('Week-agenda (W%02d):', date.IsoWeek(monday))
  var lines: list<dict<any>> = [{text: header}]
  var day = 0
  while day < 7
    var current = monday + day
    add(lines, {text: DayHeader(current)})
    lines += DayEntries(current, files, block, options)
    day += 1
  endwhile
  return lines
enddef

# `input` is a list of {path, base, lines}. `options` needs config, clock and width,
# and can have weekOffset and deadlineWarningDays.
export def RenderView(view: dict<any>, input: list<dict<any>>, options: dict<any>): list<dict<any>>
  var files: list<dict<any>> = mapnew(input, (_, file) => ({
    path: file.path,
    doc: parser.ParseOrg(file.lines, options.config, file.base),
  }))
  var separator = repeat('=', options.width - 1)
  var lines: list<dict<any>> = []
  var first = true
  for block in view.blocks
    if !first
      lines += [{text: ''}, {text: separator}]
    endif
    first = false
    if block.type ==# 'agenda'
      lines += AgendaBlock(block, files, options)
    elseif block.type ==# 'alltodo'
      lines += AllTodoBlock(block, files, options)
    else
      lines += TagsBlock(block, files, options)
    endif
  endfor
  return lines
enddef
