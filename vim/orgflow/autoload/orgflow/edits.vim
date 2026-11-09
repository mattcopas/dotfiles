vim9script
# Every edit is a pure function from old lines to new lines. files.vim then applies
# only the lines that changed, so anything the parser doesn't understand survives.
# Line numbers count from 0, to match the shared engine design.
import './parser.vim'
import './timestamp.vim' as ts

def HeadingOrThrow(lines: list<string>, line: number, config: dict<any>): dict<any>
  var doc = parser.ParseOrg(lines, config)
  for heading in doc.headings
    if heading.line == line
      return {doc: doc, heading: heading}
    endif
  endfor
  throw printf('Line %d is not a heading', line + 1)
enddef

def ReplaceKeyword(line: string, keyword: string, config: dict<any>): string
  var parsed = parser.ParseHeadingLine(line, config)
  if empty(parsed)
    return line
  endif
  var stars = repeat('*', parsed.level)
  var rest = strpart(line, strlen(stars) + 1)
  if parsed.keyword !=# ''
    rest = substitute(strpart(rest, strlen(parsed.keyword)), '^ ', '', '')
  endif
  return stars .. ' ' .. (keyword !=# '' ? keyword .. (rest !=# '' ? ' ' : '') : '') .. rest
enddef

def SequenceHead(keyword: string, config: dict<any>): string
  if keyword ==# ''
    return ''
  endif
  for sequence in config.sequences
    if index(sequence.todo, keyword) >= 0 || index(sequence.done, keyword) >= 0
      return !empty(sequence.todo) ? sequence.todo[0] : get(sequence.done, 0, '')
    endif
  endfor
  return ''
enddef

def RemoveScheduledFrom(line: string): string
  var removed = substitute(line, '\C\vSCHEDULED:\s*%(\<[^>]*\>|\[[^\]]*\])\s*', '', '')
  return substitute(removed, '\s\+$', '', '')
enddef

def EntryRepeaters(lines: list<string>, heading: dict<any>): list<dict<any>>
  var found: list<dict<any>> = []
  var at: number = heading.line
  while at < heading.entryEnd
    for stamp in ts.FindTimestamps(lines[at])
      if stamp.active && !empty(stamp.repeater) && stamp.repeater.n > 0
        add(found, {line: at, stamp: stamp})
      endif
    endfor
    at += 1
  endwhile
  return found
enddef

def ReplaceAt(line: string, column: number, oldText: string, newText: string): string
  return strpart(line, 0, column) .. newText .. strpart(line, column + strlen(oldText))
enddef

# Sets a heading's keyword ('' clears it). Completing a repeating entry moves its dates
# forward and returns it to the start of its keyword sequence, as org does, with no
# logging because the config sets org-log-repeat to nil.
export def SetTodo(input: list<string>, line: number, keyword: string, config: dict<any>, clock: dict<number>): list<string>
  var found = HeadingOrThrow(input, line, config)
  var heading = found.heading
  var lines = copy(input)
  var previous: string = heading.keyword
  var completing = keyword !=# '' && has_key(config.doneWords, keyword)
    && !(previous !=# '' && has_key(config.doneWords, previous))
  var repeats = completing ? EntryRepeaters(lines, heading) : []
  if empty(repeats)
    lines[line] = ReplaceKeyword(lines[line], keyword, config)
    return lines
  endif
  lines[line] = ReplaceKeyword(lines[line], SequenceHead(previous, config), config)
  for entry in reverse(copy(repeats))
    var stamp = entry.stamp
    lines[entry.line] = ReplaceAt(lines[entry.line], stamp.column, stamp.raw,
      ts.WithDate(stamp.raw, ts.RepeatedDate(stamp, clock)))
  endfor
  # A non-repeating SCHEDULED beside a repeater would be stale, so org drops it.
  if !empty(heading.scheduled) && empty(heading.scheduled.repeater)
    var planning = line + 1
    var cleaned = RemoveScheduledFrom(lines[planning])
    if parser.IsPlanningLine(cleaned)
      lines[planning] = cleaned
    else
      remove(lines, planning)
    endif
  endif
  return lines
enddef

# Sets SCHEDULED or DEADLINE, keeping any repeater and the planning order.
export def SetPlanning(input: list<string>, line: number, label: string, abs: number, minutes: number, config: dict<any>): list<string>
  var found = HeadingOrThrow(input, line, config)
  var heading = found.heading
  var lines = copy(input)
  var old: dict<any> = heading[tolower(label)]
  var stamp = ts.FormatStamp(abs, minutes)
  if !empty(old)
    var tail = matchlist(old.raw, '\C\v(%(\s+%(\.\+|\+\+|\+|--?)\d+[hdwmy]%(/\d+[hdwmy])?)+)\s*\>$')
    if !empty(tail)
      stamp = strpart(stamp, 0, strlen(stamp) - 1) .. tail[1] .. '>'
    endif
  endif
  var entry = label .. ': ' .. stamp
  var planning = line + 1
  if planning < len(lines) && parser.IsPlanningLine(lines[planning])
    var current = lines[planning]
    var pattern = '\C\v' .. label .. ':\s*%(\<[^>]*\>|\[[^\]]*\])'
    if current =~# pattern
      lines[planning] = substitute(current, pattern, (m) => entry, '')
    elseif label ==# 'SCHEDULED'
      var indent = matchstr(current, '^\s*')
      lines[planning] = indent .. entry .. ' ' .. strpart(current, strlen(indent))
    else
      lines[planning] = substitute(current, '\s\+$', '', '') .. ' ' .. entry
    endif
  else
    insert(lines, entry, planning)
  endif
  return lines
enddef

# Moves an existing planning stamp by a number of days. [] when there is none.
export def ShiftPlanning(input: list<string>, line: number, label: string, days: number, config: dict<any>): list<string>
  var found = HeadingOrThrow(input, line, config)
  var stamp: dict<any> = found.heading[tolower(label)]
  if empty(stamp)
    return []
  endif
  var lines = copy(input)
  var at = line + 1
  lines[at] = ReplaceAt(lines[at], stamp.column, stamp.raw, ts.WithDate(stamp.raw, stamp.abs + days))
  return lines
enddef

# Steps a priority cookie. No cookie goes to the default, and past the end removes it.
export def ChangePriority(input: list<string>, line: number, direction: string, config: dict<any>): list<string>
  HeadingOrThrow(input, line, config)
  var lines = copy(input)
  var parsed = parser.ParseHeadingLine(lines[line], config)
  var order = ['A', 'B', 'C']
  var next = ''
  if parsed.priority ==# ''
    next = config.defaultPriority
  else
    var at = index(order, parsed.priority) + (direction ==# 'up' ? -1 : 1)
    next = at >= 0 && at < len(order) ? order[at] : ''
  endif
  var stars = repeat('*', parsed.level)
  var rest = strpart(lines[line], strlen(stars) + 1)
  var prefix = ''
  if parsed.keyword !=# ''
    prefix = parsed.keyword .. ' '
    rest = substitute(strpart(rest, strlen(parsed.keyword)), '^ ', '', '')
  endif
  rest = substitute(rest, '\C\v^\[#[A-Z0-9]+\] *', '', '')
  lines[line] = stars .. ' ' .. prefix .. (next !=# '' ? '[#' .. next .. '] ' : '') .. rest
  return lines
enddef

export def SetTags(input: list<string>, line: number, tags: list<string>, config: dict<any>): list<string>
  HeadingOrThrow(input, line, config)
  var lines = copy(input)
  var stripped = substitute(lines[line], '\C\v[ \t]+:[A-Za-z0-9_@#%:]+:[ \t]*$', '', '')
  stripped = substitute(stripped, '[ \t]\+$', '', '')
  lines[line] = empty(tags) ? stripped : stripped .. ' :' .. join(tags, ':') .. ':'
  return lines
enddef

def ShiftStars(line: string, delta: number): string
  var count = strlen(matchstr(line, '^\*\+'))
  return repeat('*', count + delta) .. strpart(line, count)
enddef

# org-metaleft and org-metaright: changes this heading only, not its children.
export def ShiftHeading(input: list<string>, line: number, delta: number, config: dict<any>): list<string>
  var found = HeadingOrThrow(input, line, config)
  if found.heading.level + delta < 1
    throw 'Cannot promote to level 0'
  endif
  var lines = copy(input)
  lines[line] = ShiftStars(lines[line], delta)
  return lines
enddef

# Shifts every heading in a range of lines, leaving other lines alone. A level 1 heading
# can't be promoted, so it stays as it is.
export def ShiftHeadings(input: list<string>, first: number, last: number, delta: number, config: dict<any>): list<string>
  var lines = copy(input)
  var line = first
  while line <= last && line < len(lines)
    var parsed = parser.ParseHeadingLine(lines[line], config)
    if !empty(parsed) && parsed.level + delta >= 1
      lines[line] = ShiftStars(lines[line], delta)
    endif
    line += 1
  endwhile
  return lines
enddef

# org-shiftmetaleft and org-shiftmetaright: changes the whole subtree.
export def ShiftSubtree(input: list<string>, line: number, delta: number, config: dict<any>): list<string>
  var found = HeadingOrThrow(input, line, config)
  var heading = found.heading
  if heading.level + delta < 1
    throw 'Cannot promote to level 0'
  endif
  var lines = copy(input)
  for other in found.doc.headings
    if other.line >= heading.line && other.line < heading.subtreeEnd
      lines[other.line] = ShiftStars(lines[other.line], delta)
    endif
  endfor
  return lines
enddef

# Swaps a subtree with its neighbouring sibling. Returns {lines, line}.
export def MoveSubtree(input: list<string>, line: number, direction: string, config: dict<any>): dict<any>
  var found = HeadingOrThrow(input, line, config)
  var heading = found.heading
  var doc = found.doc
  var siblings = filter(copy(doc.headings), (_, h) => h.parent == heading.parent)
  var own = 0
  while siblings[own].line != heading.line
    own += 1
  endwhile
  var at = own + (direction ==# 'up' ? -1 : 1)
  if at < 0 || at >= len(siblings) || siblings[at].level != heading.level
    throw 'Cannot move past superior level or buffer limit'
  endif
  var other = siblings[at]
  var first = direction ==# 'up' ? other : heading
  var second = direction ==# 'up' ? heading : other
  var firstBlock = slice(input, first.line, first.subtreeEnd)
  var secondBlock = slice(input, second.line, second.subtreeEnd)
  return {
    lines: slice(input, 0, first.line) + secondBlock + firstBlock + slice(input, second.subtreeEnd),
    line: direction ==# 'up' ? first.line : first.line + len(secondBlock),
  }
enddef

# Places a captured entry under its headline, creating the headline if needed.
# `spec` has headline, prepend, entry (for example `TODO Buy milk`) and extraLines.
# Returns {lines, line}.
export def CaptureEntry(input: list<string>, spec: dict<any>, config: dict<any>): dict<any>
  var doc = parser.ParseOrg(input, config)
  var lines = copy(input)
  var target: dict<any> = {}
  for heading in doc.headings
    if heading.level == 1 && heading.title ==# spec.headline
      target = heading
      break
    endif
  endfor
  var extra: list<string> = get(spec, 'extraLines', [])

  if empty(target)
    var hasFinalNewline = !empty(lines) && lines[-1] ==# ''
    var base = hasFinalNewline ? slice(lines, 0, len(lines) - 1) : lines
    var prefix: list<string> = len(base) == 1 && base[0] ==# '' ? [] : base
    return {
      lines: prefix + ['* ' .. spec.headline, '** ' .. spec.entry] + extra + [''],
      line: len(prefix) + 1,
    }
  endif

  var at: number = target.subtreeEnd
  if get(spec, 'prepend', false)
    for heading in doc.headings
      if heading.line > target.line && heading.line < target.subtreeEnd
        at = heading.line
        break
      endif
    endfor
  endif
  # Keep blank lines that separate this subtree from the next heading.
  if at == target.subtreeEnd
    while at > target.line + 1 && trim(lines[at - 1]) ==# ''
      at -= 1
    endwhile
  endif
  var noFinalNewline = at == len(lines) && lines[at - 1] !=# ''
  var entry = [repeat('*', target.level + 1) .. ' ' .. spec.entry] + extra
  if noFinalNewline
    lines += entry + ['']
  else
    lines = slice(lines, 0, at) + entry + slice(lines, at)
  endif
  return {lines: lines, line: at}
enddef
