vim9script
# Org timestamps. A stamp is a dict: active, abs, minutes (-1 = none), endMinutes
# (-1 = none), repeater ({} = none), warning ({} = none), raw, column (a byte offset)
# and inRange. Every pattern has \C because match() and friends obey 'ignorecase'.
import './date.vim'

const STAMP = '\C\v[<[](\d{4})-(\d{2})-(\d{2})%( +[^ \t0-9>\]+.-]+)?%( +(\d{1,2}):(\d{2})%(-(\d{1,2}):(\d{2}))?)?(%( +[^>\]]{-})?) *[>\]]'

def ParseOptions(options: string): dict<any>
  var rep = matchlist(options, '\C\v%(^|\s)(\.\+|\+\+|\+)(\d+)([hdwmy])')
  var warn = matchlist(options, '\C\v%(^|\s)(--?)(\d+)([hdwmy])')
  return {
    repeater: empty(rep) ? {} : {type: rep[1], n: str2nr(rep[2]), unit: rep[3]},
    warning: empty(warn) ? {} : {once: warn[1] ==# '--', n: str2nr(warn[2]), unit: warn[3]},
  }
enddef

# Every timestamp in a line, with date ranges reported by their own flag.
export def FindTimestamps(line: string): list<dict<any>>
  var found: list<dict<any>> = []
  # Most lines have no date, so this is worth checking before the full pattern.
  if line !~# '\d\d\d\d-\d\d-\d\d'
    return found
  endif
  var from = 0
  while true
    var at = match(line, STAMP, from)
    if at < 0
      break
    endif
    var m = matchlist(line, STAMP, at)
    var raw = m[0]
    var end = at + strlen(raw)
    from = end
    var open = strpart(raw, 0, 1)
    var close = strpart(raw, strlen(raw) - 1)
    if (open ==# '<') != (close ==# '>')
      continue
    endif
    var options = ParseOptions(m[8])
    add(found, {
      active: open ==# '<',
      abs: date.ToAbs(str2nr(m[1]), str2nr(m[2]), str2nr(m[3])),
      minutes: m[4] ==# '' ? -1 : str2nr(m[4]) * 60 + str2nr(m[5]),
      endMinutes: m[6] ==# '' ? -1 : str2nr(m[6]) * 60 + str2nr(m[7]),
      repeater: options.repeater,
      warning: options.warning,
      raw: raw,
      column: at,
      inRange: strpart(line, end, 2) ==# '--' || (at >= 2 && strpart(line, at - 2, 2) ==# '--'),
    })
  endwhile
  return found
enddef

# The first stamp in some text, or {} when there is none.
export def ParseTimestamp(text: string): dict<any>
  var all = FindTimestamps(text)
  return empty(all) ? {} : all[0]
enddef

def StepDays(rep: dict<any>): number
  if rep.unit ==# 'h'
    return max([1, rep.n / 24])
  elseif rep.unit ==# 'w'
    return rep.n * 7
  endif
  return rep.n
enddef

# Months per step, or 0 when the repeater doesn't count in months.
def MonthStep(rep: dict<any>): number
  if rep.unit ==# 'm'
    return rep.n
  endif
  return rep.unit ==# 'y' ? rep.n * 12 : 0
enddef

# The first occurrence of a stamp on or after `current`, never before its base.
export def NextOccurrence(ts: dict<any>, current: number): number
  if empty(ts.repeater) || current <= ts.abs || ts.repeater.n == 0
    return ts.abs
  endif
  var months = MonthStep(ts.repeater)
  if months != 0
    var k = 0
    while date.AddMonths(ts.abs, k * months) < current
      k += 1
    endwhile
    return date.AddMonths(ts.abs, k * months)
  endif
  var step = StepDays(ts.repeater)
  return ts.abs + (current - ts.abs + step - 1) / step * step
enddef

# The last occurrence of a stamp on or before `current`.
export def PreviousOccurrence(ts: dict<any>, current: number): number
  if empty(ts.repeater) || current <= ts.abs || ts.repeater.n == 0
    return ts.abs
  endif
  var months = MonthStep(ts.repeater)
  if months != 0
    var k = 0
    while date.AddMonths(ts.abs, (k + 1) * months) <= current
      k += 1
    endwhile
    return date.AddMonths(ts.abs, k * months)
  endif
  var step = StepDays(ts.repeater)
  return ts.abs + (current - ts.abs) / step * step
enddef

# Days of warning in a `-3d` cookie, or the fallback when there is none.
export def WarningDays(ts: dict<any>, fallback: number): number
  if empty(ts.warning)
    return fallback
  endif
  var scale: dict<float> = {h: 1.0 / 24.0, d: 1.0, w: 7.0, m: 30.4, y: 365.25}
  return float2nr(floor(ts.warning.n * scale[ts.warning.unit]))
enddef

# Replaces only the date in a raw stamp, keeping time, repeater and warning.
export def WithDate(raw: string, abs: number): string
  var text = date.OrgDate(abs)
  return substitute(raw, '\C\v\d{4}-\d{2}-\d{2}%( +[^ \t0-9>\]+.-]+)?', (m) => text, '')
enddef

def Shift(abs: number, rep: dict<any>): number
  var months = MonthStep(rep)
  return months != 0 ? date.AddMonths(abs, months) : abs + StepDays(rep)
enddef

# Where a repeating stamp lands when its entry is marked done.
export def RepeatedDate(ts: dict<any>, clock: dict<number>): number
  var rep = ts.repeater
  if empty(rep)
    return ts.abs
  endif
  if rep.type ==# '.+'
    return Shift(clock.today, rep)
  elseif rep.type ==# '++'
    var abs = Shift(ts.abs, rep)
    while abs <= clock.today
      abs = Shift(abs, rep)
    endwhile
    return abs
  endif
  return Shift(ts.abs, rep)
enddef

# -1 when the text isn't understood. Dates before 1970 aren't valid here.
def ParseDatePart(text: string, today: number): number
  if text ==# '' || text ==# '.' || text ==# 'today'
    return today
  elseif text ==# 'tomorrow'
    return today + 1
  elseif text ==# 'yesterday'
    return today - 1
  endif
  var relative = matchlist(text, '\C\v^([+-])(\d+)([dwmy]?)$')
  if !empty(relative)
    var n = str2nr(relative[2]) * (relative[1] ==# '-' ? -1 : 1)
    if relative[3] ==# 'w'
      return today + n * 7
    elseif relative[3] ==# 'm'
      return date.AddMonths(today, n)
    elseif relative[3] ==# 'y'
      return date.AddMonths(today, n * 12)
    endif
    return today + n
  endif
  var day = 0
  while day < 7
    var name = tolower(date.DAY_SHORT[day])
    if strpart(text, 0, 3) ==# name
      return today + ((day - date.Weekday(today) + 7) % 7)
    endif
    day += 1
  endwhile
  var full = matchlist(text, '\C\v^(\d{4})-(\d{1,2})-(\d{1,2})$')
  if !empty(full)
    return date.ToAbs(str2nr(full[1]), str2nr(full[2]), str2nr(full[3]))
  endif
  var monthDay = matchlist(text, '\C\v^(\d{1,2})-(\d{1,2})$')
  if !empty(monthDay)
    var y = date.FromAbs(today).y
    var abs = date.ToAbs(y, str2nr(monthDay[1]), str2nr(monthDay[2]))
    return abs < today ? date.ToAbs(y + 1, str2nr(monthDay[1]), str2nr(monthDay[2])) : abs
  endif
  var dayOnly = matchlist(text, '\C\v^(\d{1,2})$')
  if !empty(dayOnly)
    var c = date.FromAbs(today)
    var abs = date.ToAbs(c.y, c.m, str2nr(dayOnly[1]))
    return abs < today ? date.AddMonths(abs, 1) : abs
  endif
  return -1
enddef

# Reads a date as typed at a schedule prompt: `+1d`, `-2w`, `.`, `today`, `tomorrow`,
# `fri`, `2026-11-12`, `11-12` or `12`, with an optional `14:30`. Returns {} when the
# text isn't understood, otherwise {abs, minutes} with minutes -1 for no time.
export def ParseDateInput(input: string, today: number): dict<number>
  var text = tolower(trim(input))
  var minutes = -1
  var at = match(text, '\C\v%(^|\s)\d{1,2}:\d{2}$')
  if at >= 0
    var time = matchlist(text, '\C\v(\d{1,2}):(\d{2})$')
    minutes = str2nr(time[1]) * 60 + str2nr(time[2])
    text = trim(strpart(text, 0, at))
  endif
  var abs = ParseDatePart(text, today)
  return abs < 0 ? {} : {abs: abs, minutes: minutes}
enddef

export def FormatStamp(abs: number, minutes: number): string
  if minutes < 0
    return '<' .. date.OrgDate(abs) .. '>'
  endif
  return printf('<%s %02d:%02d>', date.OrgDate(abs), minutes / 60, minutes % 60)
enddef
