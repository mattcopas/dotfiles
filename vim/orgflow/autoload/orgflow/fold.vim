vim9script
# Org folding on Vim's own folds. Vim can report fold state, so TAB works out where it
# is in the cycle from the buffer each time and can't drift out of step.
#
# A closed fold always takes one screen line. So a parent's body gets its own fold only
# when it has child headings, because that's the only case needing one: closing a leaf
# heading hides its body without any extra line.

const DRAWER_START = '\c^\s*:\(PROPERTIES\|LOGBOOK\):\s*$'
const DRAWER_END = '\c^\s*:END:\s*$'
const BLOCK_START = '\c^\s*#+begin_'
const BLOCK_END = '\c^\s*#+end_'

def Level(lnum: number): number
  return strlen(matchstr(getline(lnum), '^\*\+\ze '))
enddef

def IsDrawerStart(lnum: number): bool
  return getline(lnum) =~ DRAWER_START
enddef

def SubtreeEnd(lnum: number): number
  var level = Level(lnum)
  var last = line('$')
  var at = lnum + 1
  while at <= last
    var other = Level(at)
    if other > 0 && other <= level
      return at - 1
    endif
    at += 1
  endwhile
  return last
enddef

# Whether the heading whose body starts at lnum has children below that body.
def BodyHasChildren(lnum: number, headingLevel: number): bool
  var last = line('$')
  var at = lnum
  while at <= last
    var other = Level(at)
    if other > 0
      return other > headingLevel
    endif
    at += 1
  endwhile
  return false
enddef

export def Expr(): string
  var lnum = v:lnum
  var line = getline(lnum)
  var level = strlen(matchstr(line, '^\*\+\ze '))
  if level > 0
    return '>' .. level
  endif
  if lnum > 1
    var above = strlen(matchstr(getline(lnum - 1), '^\*\+\ze '))
    if above > 0 && BodyHasChildren(lnum, above)
      return '>' .. (above + 1)
    endif
  endif
  if line =~ DRAWER_START || line =~ BLOCK_START
    return 'a1'
  endif
  if line =~ DRAWER_END || line =~ BLOCK_END
    return 's1'
  endif
  return '='
enddef

export def Text(): string
  var count = v:foldend - v:foldstart + 1
  var line = getline(v:foldstart)
  return Level(v:foldstart) > 0
    ? line .. ' …'
    : matchstr(line, '^\s*') .. '… ' .. count .. ' lines'
enddef

# Closes one fold at a line. Calling this twice on a line would close its parent.
def CloseAt(lnum: number)
  execute 'silent! :' .. lnum .. 'foldclose'
enddef

# Closes every fold below a heading but leaves that heading open. Works bottom up, so
# each close hits the innermost fold, which can't close a parent by accident.
def CloseBelow(start: number, end: number)
  execute 'silent! :' .. start .. ',' .. end .. 'foldopen!'
  var lnum = end
  while lnum > start
    if Level(lnum) > 0 || foldlevel(lnum) > foldlevel(lnum - 1)
      CloseAt(lnum)
    endif
    lnum -= 1
  endwhile
enddef

# Opens a range, but keeps drawers shut, as org does.
def OpenAll(start: number, end: number)
  execute 'silent! :' .. start .. ',' .. end .. 'foldopen!'
  var lnum = end
  while lnum >= start
    if IsDrawerStart(lnum) && foldlevel(lnum) > foldlevel(lnum - 1)
      CloseAt(lnum)
    endif
    lnum -= 1
  endwhile
enddef

def HasClosedHeadingBelow(start: number, end: number): bool
  var lnum = start + 1
  while lnum <= end
    if foldclosed(lnum) > 0 && !IsDrawerStart(foldclosed(lnum))
      return true
    endif
    var closedEnd = foldclosedend(lnum)
    lnum = closedEnd > 0 ? closedEnd + 1 : lnum + 1
  endwhile
  return false
enddef

def HasChildHeading(start: number, end: number): bool
  var lnum = start + 1
  while lnum <= end
    if Level(lnum) > 0
      return true
    endif
    lnum += 1
  endwhile
  return false
enddef

# FOLDED, CHILDREN or SUBTREE, for a heading. Returns the state it moved to.
export def Cycle(lnum: number): string
  var end = SubtreeEnd(lnum)
  if end == lnum
    return 'EMPTY'
  endif
  if foldclosed(lnum) > 0
    if HasChildHeading(lnum, end)
      CloseBelow(lnum, end)
      return 'CHILDREN'
    endif
    OpenAll(lnum, end)
    return 'SUBTREE'
  endif
  if HasClosedHeadingBelow(lnum, end)
    OpenAll(lnum, end)
    return 'SUBTREE'
  endif
  CloseAt(lnum)
  return 'FOLDED'
enddef

def IsOverview(): bool
  var lnum = 1
  var last = line('$')
  while lnum <= last
    if Level(lnum) == 1
      var end = SubtreeEnd(lnum)
      if end > lnum && foldclosed(lnum) < 0
        return false
      endif
      lnum = end
    endif
    lnum += 1
  endwhile
  return true
enddef

def ApplyContents()
  normal! zR
  var last = line('$')
  var lnum = last
  while lnum >= 1
    var level = Level(lnum)
    if level > 0
      # A leaf closes whole, and a parent stays open to show its children.
      if !HasChildHeading(lnum, SubtreeEnd(lnum))
        CloseAt(lnum)
      endif
    elseif lnum > 1 && foldlevel(lnum) > foldlevel(lnum - 1)
      CloseAt(lnum)
    endif
    lnum -= 1
  endwhile
enddef

export def GlobalCycle(): string
  var view = winsaveview()
  var state = ''
  if IsOverview()
    ApplyContents()
    state = 'CONTENTS'
  elseif HasClosedHeadingBelow(0, line('$'))
    normal! zR
    OpenAll(1, line('$'))
    state = 'SHOW ALL'
  else
    normal! zM
    state = 'OVERVIEW'
  endif
  winrestview(view)
  return state
enddef

# While typing, new headings mustn't fold shut around the cursor, and recalculating
# folds on every keystroke is wasted work.
export def InsertEnter()
  setlocal foldmethod=manual
enddef

export def InsertLeave()
  setlocal foldmethod=expr
  silent! normal! zv
enddef
