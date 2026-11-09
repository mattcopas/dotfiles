vim9script
# org-journal's monthly files: finding the right day, adding a day heading, carrying
# unfinished items over, and starting a timed entry.
import './date.vim'
import './match.vim' as matcher
import './parser.vim'

export def JournalFileName(abs: number, config: dict<any>): string
  return date.FormatDate(config.fileFormat, abs)
enddef

# Days are found through the CREATED property, because that's what org-journal reads.
def DayEntries(doc: dict<any>): list<dict<any>>
  var days: list<dict<any>> = []
  for heading in doc.headings
    if heading.level != 1
      continue
    endif
    var m = matchlist(get(heading.properties, 'CREATED', ''), '\C\v^(\d{4})(\d{2})(\d{2})$')
    if !empty(m)
      add(days, {
        abs: date.ToAbs(str2nr(m[1]), str2nr(m[2]), str2nr(m[3])),
        line: heading.line,
        subtreeEnd: heading.subtreeEnd,
        headingIndex: heading.index,
      })
    endif
  endfor
  return days
enddef

# The latest day before `before` in a file, or -1 when there isn't one.
export def LatestDayBefore(lines: list<string>, before: number, config: dict<any>): number
  var latest = -1
  for day in DayEntries(parser.ParseOrg(lines, config))
    if day.abs < before && day.abs > latest
      latest = day.abs
    endif
  endfor
  return latest
enddef

# Reads the first date a file can hold from its name, for example `Nov-2026.org`.
# Returns -1 when the name doesn't fit the format.
export def FileNameToMonth(name: string, config: dict<any>): number
  var pattern = ''
  var order: list<string> = []
  var rest: string = config.fileFormat
  while rest !=# ''
    var token = strpart(rest, 0, 2)
    if token ==# '%Y'
      pattern ..= '(\d{4})'
      add(order, 'y')
      rest = strpart(rest, 2)
    elseif token ==# '%b'
      pattern ..= '(\a{3})'
      add(order, 'b')
      rest = strpart(rest, 2)
    elseif token ==# '%m'
      pattern ..= '(\d{2})'
      add(order, 'm')
      rest = strpart(rest, 2)
    else
      var char = strcharpart(rest, 0, 1)
      pattern ..= char =~# '[A-Za-z0-9_]' || char2nr(char) > 127 ? char : '\' .. char
      rest = strpart(rest, strlen(char))
    endif
  endwhile
  var m = matchlist(name, '\C\v^' .. pattern .. '$')
  if empty(m) || index(order, 'y') < 0
    return -1
  endif
  var year = 0
  var month = 1
  var i = 0
  for kind in order
    i += 1
    if kind ==# 'y'
      year = str2nr(m[i])
    elseif kind ==# 'm'
      month = str2nr(m[i])
    else
      var found = index(map(copy(date.MONTH_SHORT), (_, s) => tolower(s)), tolower(m[i]))
      if found < 0
        return -1
      endif
      month = found + 1
    endif
  endfor
  return date.ToAbs(year, month, 1)
enddef

# Ports org-journal--carryover, including how it de-duplicates shared parents.
# Returns {text, remaining}, or {} when nothing carries over.
def CollectCarryover(lines: list<string>, doc: dict<any>, day: dict<any>, parsedMatch: dict<any>, config: dict<any>, clock: dict<number>): dict<any>
  var paths: list<any> = []
  var headings: list<dict<any>> = slice(doc.headings, day.headingIndex)
  var i = 0
  while i < len(headings) && headings[i].line < day.subtreeEnd
    var heading = headings[i]
    if !matcher.Matches(parsedMatch, heading, config, clock)
      i += 1
      continue
    endif
    var path: list<dict<any>> = []
    var parentIndex: number = heading.parent
    while parentIndex >= 0 && doc.headings[parentIndex].level >= 2
      var parent = doc.headings[parentIndex]
      insert(path, {
        start: parent.line,
        end: parent.entryEnd,
        text: slice(lines, parent.line, parent.entryEnd),
      })
      parentIndex = parent.parent
    endwhile
    add(path, {
      start: heading.line,
      end: heading.subtreeEnd,
      text: slice(lines, heading.line, heading.subtreeEnd),
    })
    add(paths, path)
    while i < len(headings) && headings[i].line < heading.subtreeEnd
      i += 1
    endwhile
  endwhile
  if empty(paths)
    return {}
  endif

  var cleared: list<dict<any>> = []
  var text: list<string> = []
  var previous: list<any> = []
  var hasPrevious = false
  for path in paths
    var index = 0
    for step in path
      # cl-loop's `count` advances before the body, so org-journal really does compare
      # against the entry one past the matching depth.
      var counter = index + 1
      index += 1
      var noOther = !hasPrevious || counter >= len(previous)
      if noOther || step.start > previous[counter].start
        text += step.text
        add(cleared, step)
      endif
    endfor
    previous = path
    hasPrevious = true
  endfor

  var deleted: list<bool> = repeat([false], len(lines))
  for step in reverse(copy(cleared))
    var last = step.end - 1
    var owner: dict<any> = doc.headings[0]
    for heading in doc.headings
      if heading.line <= last && !deleted[heading.line]
        owner = heading
      endif
    endfor
    var next: dict<any> = {}
    for heading in doc.headings
      if heading.line >= step.end && !deleted[heading.line]
        next = heading
        break
      endif
    endfor
    var hasChild = !empty(next) && owner.line < next.line && next.level > owner.level
    if !hasChild
      var at: number = step.start
      while at < step.end
        deleted[at] = true
        at += 1
      endwhile
    endif
  endfor
  var remaining: list<string> = []
  var at = 0
  while at < len(lines)
    if !deleted[at]
      add(remaining, lines[at])
    endif
    at += 1
  endwhile
  return {text: text, remaining: remaining}
enddef

# Plain date stamps in carried text move to today. Planning lines keep their dates.
def RefreshStamps(lines: list<string>, today: number): list<string>
  var stamp = '<' .. date.OrgDate(today) .. '>'
  return mapnew(lines, (_, line) => line =~# '\C\v<(SCHEDULED|DEADLINE):'
    ? line
    : substitute(line, '\C\v\<\d{4}-\d{2}-\d{2}%( [A-Za-z]+)?\>', (m) => stamp, 'g'))
enddef

def DayHeader(abs: number, config: dict<any>): list<string>
  var c = date.FromAbs(abs)
  return [
    '* ' .. date.FormatDate(config.dateFormat, abs),
    ':PROPERTIES:',
    printf(':CREATED:  %d%02d%02d', c.y, c.m, c.d),
    ':END:',
  ]
enddef

def StripFinal(lines: list<string>): dict<any>
  if !empty(lines) && lines[-1] ==# ''
    return {lines: slice(lines, 0, len(lines) - 1), finalNewline: true}
  endif
  return {lines: lines, finalNewline: false}
enddef

# `input` has clock, config (fileFormat, dateFormat, carryover), orgConfig,
# currentLines (today's file, [''] when new), and previousLines when another file holds
# the most recent earlier day. Returns {current, previous, line}: new lines for today's
# file, new lines for the older file ([] when it didn't change) and the new entry's line.
export def PlanNewEntry(input: dict<any>): dict<any>
  var clock: dict<number> = input.clock
  var config: dict<any> = input.config
  var orgConfig: dict<any> = input.orgConfig
  var today = clock.today
  var lines: list<string> = StripFinal(input.currentLines).lines
  var hasPrevious = has_key(input, 'previousLines')
  var previous: dict<any> = hasPrevious ? StripFinal(input.previousLines) : {}
  var parsedMatch = matcher.ParseMatch(config.carryover)

  # Add today's heading if it's missing, in date order.
  var days0 = DayEntries(parser.ParseOrg(lines, orgConfig))
  if empty(filter(copy(days0), (_, d) => d.abs == today))
    var later = filter(copy(days0), (_, d) => d.abs > today)
    var at: number = !empty(later) ? later[0].line : len(lines)
    lines = slice(lines, 0, at) + DayHeader(today, config) + slice(lines, at)
  endif

  # Carry items over from the most recent earlier day.
  var inCurrent = filter(DayEntries(parser.ParseOrg(lines, orgConfig)), (_, d) => d.abs < today)
  var donor = !empty(inCurrent) ? 'current' : (hasPrevious ? 'previous' : '')
  var carried: list<string> = []
  var newPrevious: list<string> = []
  if donor !=# '' && trim(config.carryover) !=# ''
    var source: list<string> = donor ==# 'current' ? lines : previous.lines
    var doc = parser.ParseOrg(source, orgConfig)
    var days = filter(DayEntries(doc), (_, d) => d.abs < today)
    if !empty(days)
      var latest = days[0]
      for day in days
        if day.abs > latest.abs
          latest = day
        endif
      endfor
      var result = CollectCarryover(source, doc, latest, parsedMatch, orgConfig, clock)
      if !empty(result)
        carried = RefreshStamps(result.text, today)
        if donor ==# 'current'
          lines = result.remaining
        else
          newPrevious = result.remaining + (previous.finalNewline ? [''] : [])
        endif
      endif
    endif
  endif

  # Add carried items and the new entry at the end of today's subtree.
  var todayEntries = filter(DayEntries(parser.ParseOrg(lines, orgConfig)), (_, d) => d.abs == today)
  if empty(todayEntries)
    throw printf('Journal entry for %s went missing', date.IsoDate(today))
  endif
  var entry = todayEntries[0]
  var at: number = entry.subtreeEnd
  while at > entry.line + 1 && trim(lines[at - 1]) ==# ''
    at -= 1
  endwhile
  var added = carried + ['** ' .. date.FormatDate('%H:%M', today, clock.minutes) .. ' ']
  return {
    current: slice(lines, 0, at) + added + slice(lines, at) + [''],
    previous: newPrevious,
    line: max([at + len(added) - 1, entry.line]),
  }
enddef
