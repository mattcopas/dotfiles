vim9script
# Org structure. "Lines" here always mean text split on newlines, so a file ending in
# a newline has a final empty element, which keeps edits byte-exact.
import './timestamp.vim' as ts

# Reads org's own notation: ['TODO(t)', 'IN PROGRESS(p)', '|', 'DONE(d)'].
export def MakeConfig(sequences: list<any>): dict<any>
  var keys: dict<string> = {}
  var parsed: list<dict<any>> = []
  var todoWords: dict<bool> = {}
  var doneWords: dict<bool> = {}
  for sequence in sequences
    var names: list<string> = []
    for item in sequence
      var m = matchlist(item, '\C\v^(.{-})%(\(([^)/]*)[^)]*\))?$')
      add(names, item ==# '|' ? '|' : m[1])
      if item !=# '|' && m[2] !=# ''
        keys[m[1]] = m[2]
      endif
    endfor
    var bar = index(names, '|')
    var todo = bar >= 0 ? slice(names, 0, bar) : slice(names, 0, len(names) - 1)
    var done = bar >= 0 ? slice(names, bar + 1) : slice(names, len(names) - 1)
    add(parsed, {todo: todo, done: done})
    for name in todo
      todoWords[name] = true
    endfor
    for name in done
      doneWords[name] = true
    endfor
  endfor
  # Keywords may contain spaces, so they're tried longest first.
  var keywords: list<string> = []
  for sequence in parsed
    for name in sequence.todo + sequence.done
      if index(keywords, name) < 0
        add(keywords, name)
      endif
    endfor
  endfor
  sort(keywords, (a, b) => strlen(b) - strlen(a))
  return {
    sequences: parsed,
    keys: keys,
    defaultPriority: 'B',
    keywords: keywords,
    doneWords: doneWords,
    todoWords: todoWords,
  }
enddef

const TAGS = '\C\v%(^|[ \t]+):([A-Za-z0-9_@#%:]+):[ \t]*$'

export def IsHeadingLine(line: string): bool
  return line =~# '^\*\+ '
enddef

# {level, keyword, priority, title, text, tags}, or {} for anything else.
export def ParseHeadingLine(line: string, config: dict<any>): dict<any>
  var m = matchlist(line, '\C^\(\*\+\) \(.*\)$')
  if empty(m)
    return {}
  endif
  var body = m[2]
  var tags: list<string> = []
  var tagAt = match(body, TAGS)
  if tagAt >= 0
    tags = filter(split(matchlist(body, TAGS)[1], ':'), (_, t) => t !=# '')
    body = strpart(body, 0, tagAt)
  endif
  var text = substitute(body, '[ \t]\+$', '', '')
  var rest = text
  var keyword = ''
  for candidate in config.keywords
    if rest ==# candidate || strpart(rest, 0, strlen(candidate) + 1) ==# candidate .. ' '
      keyword = candidate
      rest = substitute(strpart(rest, strlen(candidate)), '^ \+', '', '')
      break
    endif
  endfor
  var priority = ''
  var cookie = matchlist(rest, '\C\v^\[#([A-Z0-9]+)\] *')
  if !empty(cookie)
    priority = cookie[1]
    rest = strpart(rest, strlen(cookie[0]))
  endif
  return {
    level: strlen(m[1]),
    keyword: keyword,
    priority: priority,
    title: rest,
    text: text,
    tags: tags,
  }
enddef

def ReadKeywordLines(lines: list<string>): dict<any>
  var fileTags: list<string> = []
  var category = ''
  var hasCategory = false
  for line in lines
    if IsHeadingLine(line)
      break
    endif
    if strpart(line, 0, 2) !=# '#+'
      continue
    endif
    var m = matchlist(line, '\C\v^#\+([A-Za-z_]+):[ \t]*(.{-})[ \t]*$')
    if empty(m)
      continue
    endif
    var key = toupper(m[1])
    if key ==# 'FILETAGS'
      fileTags += filter(split(m[2], ':'), (_, t) => t !=# '')
    elseif key ==# 'CATEGORY'
      category = m[2]
      hasCategory = true
    endif
  endfor
  return {fileTags: fileTags, category: category, hasCategory: hasCategory}
enddef

const PLANNING = '\C^\s*\(SCHEDULED\|DEADLINE\|CLOSED\):'

export def IsPlanningLine(line: string): bool
  return line =~# PLANNING
enddef

def ReadPlanning(heading: dict<any>, line: string)
  heading.scheduled = {}
  heading.deadline = {}
  heading.closed = {}
  if line !~# PLANNING
    return
  endif
  for stamp in ts.FindTimestamps(line)
    var label = matchlist(strpart(line, 0, stamp.column), '\C\v(SCHEDULED|DEADLINE|CLOSED):\s*$')
    if empty(label)
      continue
    endif
    if label[1] ==# 'SCHEDULED'
      heading.scheduled = stamp
    elseif label[1] ==# 'DEADLINE'
      heading.deadline = stamp
    else
      heading.closed = stamp
    endif
  endfor
enddef

def ReadProperties(lines: list<string>, from: number, end: number): dict<string>
  var properties: dict<string> = {}
  var i = from
  if i < end && lines[i] =~# PLANNING
    i += 1
  endif
  if i >= end || lines[i] !~# '\C^\s*:PROPERTIES:\s*$'
    return properties
  endif
  i += 1
  while i < end && lines[i] !~# '\C^\s*:END:\s*$'
    var m = matchlist(lines[i], '\C\v^\s*:([^: \t]+):\s*(.{-})\s*$')
    if !empty(m)
      properties[toupper(m[1])] = m[2]
    endif
    i += 1
  endwhile
  return properties
enddef

def Unique(items: list<string>): list<string>
  var out: list<string> = []
  for item in items
    if index(out, item) < 0
      add(out, item)
    endif
  endfor
  return out
enddef

export def ParseOrg(lines: list<string>, config: dict<any>, fileBase: string = ''): dict<any>
  var keywordLines = ReadKeywordLines(lines)
  var fileCategory = keywordLines.hasCategory ? keywordLines.category : fileBase
  var headings: list<dict<any>> = []
  var stack: list<dict<any>> = []
  var lineNumber = 0
  for line in lines
    if strpart(line, 0, 1) ==# '*'
      var parsed = ParseHeadingLine(line, config)
      if !empty(parsed)
        while !empty(stack) && stack[-1].level >= parsed.level
          remove(stack, -1)
        endwhile
        var hasParent = !empty(stack)
        var parent: dict<any> = hasParent ? stack[-1] : {}
        var inherited: list<string> = hasParent
          ? parent.inheritedTags + parent.localTags
          : keywordLines.fileTags
        var localTags: list<string> = parsed.tags
        var heading: dict<any> = {
          index: len(headings),
          line: lineNumber,
          level: parsed.level,
          keyword: parsed.keyword,
          priority: parsed.priority,
          title: parsed.title,
          text: parsed.text,
          localTags: localTags,
          inheritedTags: filter(Unique(inherited), (_, t) => index(localTags, t) < 0),
          scheduled: {},
          deadline: {},
          closed: {},
          properties: {},
          category: hasParent ? parent.category : fileCategory,
          entryEnd: len(lines),
          subtreeEnd: len(lines),
          parent: hasParent ? parent.index : -1,
        }
        add(headings, heading)
        add(stack, heading)
      endif
    endif
    lineNumber += 1
  endfor

  # A final empty element isn't a real line. It must not count as part of the last
  # subtree, or moving that subtree moves the file's final newline with it.
  var count = len(lines)
  var contentEnd = count > 0 && lines[count - 1] ==# '' ? count - 1 : count
  var total = len(headings)
  var i = 0
  while i < total
    var heading = headings[i]
    heading.entryEnd = i + 1 < total ? headings[i + 1].line : contentEnd
    var next = i + 1
    while next < total && headings[next].level > heading.level
      next += 1
    endwhile
    heading.subtreeEnd = next < total ? headings[next].line : contentEnd
    ReadPlanning(heading, heading.line + 1 < count ? lines[heading.line + 1] : '')
    heading.properties = ReadProperties(lines, heading.line + 1, heading.entryEnd)
    if has_key(heading.properties, 'CATEGORY') && heading.properties.CATEGORY !=# ''
      var own = heading.properties.CATEGORY
      heading.category = own
      var j = i + 1
      while j < total && headings[j].level > heading.level
        headings[j].category = own
        j += 1
      endwhile
    endif
    i += 1
  endwhile

  return {lines: lines, headings: headings, fileTags: keywordLines.fileTags, category: fileCategory}
enddef

# The heading whose entry contains a line, or {} before the first heading.
export def HeadingAt(doc: dict<any>, line: number): dict<any>
  var found: dict<any> = {}
  for heading in doc.headings
    if heading.line > line
      break
    endif
    found = heading
  endfor
  return found
enddef
