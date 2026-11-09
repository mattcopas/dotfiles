vim9script
# Org's tag and property match language, for example `+work+PRIORITY="A"`,
# `+SCHEDULED="<today>"` or `work-done|TODO="WAIT"`. A {regex} term uses Vim's very
# magic syntax, which is close to but not the same as Emacs regexps.
import './timestamp.vim' as ts

const TERM = '\C\v^([+-]?)%(([A-Za-z_][A-Za-z0-9_-]*)(\<\>|\<\=|\>\=|\=|\<|\>)("%([^"\\]|\\.)*"|\{[^}]*\}|-?\d+%(\.\d+)?)|\{([^}]*)\}|([A-Za-z0-9_@#%]+))'

def SplitTopLevel(text: string, separator: string): list<string>
  var parts: list<string> = []
  var current = ''
  var quote = false
  var brace = 0
  for char in split(text, '\zs')
    if char ==# '"'
      quote = !quote
    elseif !quote && char ==# '{'
      brace += 1
    elseif !quote && char ==# '}'
      brace -= 1
    endif
    if char ==# separator && !quote && brace == 0
      add(parts, current)
      current = ''
    else
      current ..= char
    endif
  endfor
  add(parts, current)
  return parts
enddef

export def ParseMatch(expression: string, todoOnly: bool = false): dict<any>
  var pieces = SplitTopLevel(expression, '/')
  var tagPart = pieces[0]
  var todoPart = join(slice(pieces, 1), '/')
  var todoFilter: list<string> = []
  var hasFilter = false
  var onlyNotDone = todoOnly
  if todoPart !=# ''
    var clean = substitute(todoPart, '^!', '', '')
    if strpart(todoPart, 0, 1) ==# '!'
      onlyNotDone = true
    endif
    if clean !=# ''
      todoFilter = split(clean, '|', 1)
      hasFilter = true
    endif
  endif
  var groups: list<any> = []
  for group in SplitTopLevel(tagPart, '|')
    var terms: list<dict<any>> = []
    var rest = trim(group)
    while rest !=# ''
      if strpart(rest, 0, 1) ==# '&'
        rest = strpart(rest, 1)
        continue
      endif
      var found = matchlist(rest, TERM)
      if empty(found) || found[0] ==# ''
        throw printf('Can''t read match expression at "%s"', rest)
      endif
      rest = strpart(rest, strlen(found[0]))
      var negate = found[1] ==# '-'
      if found[2] !=# ''
        var raw = found[4]
        var first = strpart(raw, 0, 1)
        var isRegex = first ==# '{'
        var value = first ==# '"' || isRegex ? strpart(raw, 1, strlen(raw) - 2) : raw
        add(terms, {kind: 'prop', negate: negate, name: toupper(found[2]), op: found[3], value: value, isRegex: isRegex})
      elseif found[6] !=# ''
        add(terms, {kind: 'tag', negate: negate, tag: found[6]})
      else
        add(terms, {kind: 'regex', negate: negate, regex: found[5]})
      endif
    endwhile
    add(groups, terms)
  endfor
  return {groups: groups, todoOnly: onlyNotDone, todoFilter: todoFilter, hasFilter: hasFilter}
enddef

def CompareNumbers(a: float, b: float, op: string): bool
  if op ==# '='
    return a == b
  elseif op ==# '<>'
    return a != b
  elseif op ==# '<'
    return a < b
  elseif op ==# '<='
    return a <= b
  elseif op ==# '>'
    return a > b
  endif
  return a >= b
enddef

def CompareStrings(a: string, b: string, op: string): bool
  if op ==# '='
    return a ==# b
  elseif op ==# '<>'
    return a !=# b
  elseif op ==# '<'
    return a <# b
  elseif op ==# '<='
    return a <=# b
  elseif op ==# '>'
    return a ># b
  endif
  return a >=# b
enddef

# Stamps compare as exact instants, like org. A stamp with a time of day is not equal
# to `<today>`, which means midnight, so `SCHEDULED="<today>"` skips items scheduled
# at a specific time. Surprising, but that's what the agenda does.
def StampMinutes(stamp: dict<any>): number
  return stamp.abs * 1440 + max([stamp.minutes, 0])
enddef

# -1 when the value isn't a date.
def SpecMinutes(value: string, clock: dict<number>): number
  var inner = trim(strpart(value, 1, strlen(value) - 2))
  if inner ==# 'now'
    return clock.today * 1440 + clock.minutes
  endif
  var parsed = ts.ParseDateInput(inner, clock.today)
  return empty(parsed) ? -1 : parsed.abs * 1440 + max([parsed.minutes, 0])
enddef

const NUMERIC = '\C\v^-?\d+%(\.\d+)?$'

def EvaluateProp(term: dict<any>, heading: dict<any>, allTags: list<string>, config: dict<any>, clock: dict<number>): bool
  var name: string = term.name
  if name ==# 'SCHEDULED' || name ==# 'DEADLINE' || name ==# 'CLOSED'
    var stamp: dict<any> = heading[tolower(name)]
    if empty(stamp)
      return term.op ==# '<>'
    endif
    var target = SpecMinutes(term.value, clock)
    if target < 0
      return false
    endif
    return CompareNumbers(0.0 + StampMinutes(stamp), 0.0 + target, term.op)
  endif
  var actual = ''
  if name ==# 'TODO'
    actual = heading.keyword
  elseif name ==# 'PRIORITY'
    actual = heading.priority !=# '' ? heading.priority : config.defaultPriority
  elseif name ==# 'LEVEL'
    return CompareNumbers(0.0 + heading.level, str2float(term.value), term.op)
  elseif name ==# 'CATEGORY'
    actual = heading.category
  elseif name ==# 'ITEM'
    actual = heading.text
  elseif name ==# 'TAGS'
    actual = empty(allTags) ? '' : ':' .. join(allTags, ':') .. ':'
  else
    actual = get(heading.properties, name, '')
  endif
  if term.isRegex
    var hit = actual =~# '\v' .. term.value
    return term.op ==# '<>' ? !hit : hit
  endif
  if term.value =~# NUMERIC && (actual =~# NUMERIC || actual ==# '')
    return CompareNumbers(str2float(actual), str2float(term.value), term.op)
  endif
  return CompareStrings(actual, term.value, term.op)
enddef

def TermHits(term: dict<any>, heading: dict<any>, allTags: list<string>, config: dict<any>, clock: dict<number>): bool
  if term.kind ==# 'tag'
    return index(allTags, term.tag) >= 0
  elseif term.kind ==# 'regex'
    return heading.text =~# '\v' .. term.regex
  endif
  return EvaluateProp(term, heading, allTags, config, clock)
enddef

export def Matches(matcher: dict<any>, heading: dict<any>, config: dict<any>, clock: dict<number>): bool
  var keyword: string = heading.keyword
  if matcher.todoOnly && (keyword ==# '' || has_key(config.doneWords, keyword))
    return false
  endif
  if matcher.hasFilter && (keyword ==# '' || index(matcher.todoFilter, keyword) < 0)
    return false
  endif
  var allTags: list<string> = heading.inheritedTags + heading.localTags
  for group in matcher.groups
    var all = true
    for term in group
      var hit = TermHits(term, heading, allTags, config, clock)
      if term.negate ? hit : !hit
        all = false
        break
      endif
    endfor
    if all
      return true
    endif
  endfor
  return false
enddef
