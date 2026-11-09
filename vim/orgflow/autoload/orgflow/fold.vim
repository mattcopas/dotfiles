vim9script
# Org folding on Vim's own folds. Vim can report fold state, so TAB works out where it
# is in the cycle from the buffer each time and can't drift out of step.
#
# Vim draws a closed fold in one flat colour, so a heading is never inside its own fold:
# only what's under it folds, which keeps headings and keywords in their real colours. A
# heading of level N sits at fold level N - 1 and its content at level N. That closed
# content needs a row of its own, because a closed fold always takes a screen line. A
# parent's body has a further fold inside that, so it can hide while its children show.

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
  var above = lnum > 1 ? strlen(matchstr(getline(lnum - 1), '^\*\+\ze ')) : 0
  if level > 0
    # A child straight under its parent is the first line of the parent's content.
    return above > 0 && above < level ? '>' .. (level - 1) : string(level - 1)
  endif
  var opensBlock = line =~ DRAWER_START || line =~ BLOCK_START
  if above > 0
    var depth = BodyHasChildren(lnum, above) ? above + 1 : above
    return '>' .. (opensBlock ? depth + 1 : depth)
  endif
  if opensBlock
    return 'a1'
  endif
  if line =~ DRAWER_END || line =~ BLOCK_END
    return 's1'
  endif
  return '='
enddef

export def Text(): string
  var count = v:foldend - v:foldstart + 1
  return repeat(' ', v:foldlevel) .. printf('… %d %s', count, count == 1 ? 'line' : 'lines')
enddef

# Closes one fold at a line. Calling this twice on a line would close its parent.
def CloseAt(lnum: number)
  execute 'silent! :' .. lnum .. 'foldclose'
enddef

# Closes everything under a heading. Its content can begin with folds nested inside the
# outer one, so this closes one level at a time until the whole subtree is covered.
def CloseContent(heading: number)
  var end = SubtreeEnd(heading)
  if end == heading
    return
  endif
  var tries = 0
  while foldclosedend(heading + 1) < end && tries < 12
    CloseAt(heading + 1)
    tries += 1
  endwhile
enddef

def IsContentClosed(heading: number): bool
  var end = SubtreeEnd(heading)
  return end > heading && foldclosedend(heading + 1) >= end
enddef

# Shows a heading's child headings, with everything under each of them closed. Works
# bottom up, so each close hits the innermost fold.
def ShowChildren(start: number, end: number)
  execute 'silent! :' .. (start + 1) .. ',' .. end .. 'foldopen!'
  var lnum = end
  while lnum > start
    if Level(lnum) > 0
      CloseContent(lnum)
    endif
    lnum -= 1
  endwhile
  # The heading's own body, which comes before its first child.
  if Level(start + 1) == 0
    CloseAt(start + 1)
  endif
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

def IsClosedDrawer(lnum: number): bool
  return IsDrawerStart(foldclosed(lnum)) && getline(foldclosedend(lnum)) =~ DRAWER_END
enddef

def HasClosedContent(start: number, end: number): bool
  var lnum = start + 1
  while lnum <= end
    if foldclosed(lnum) > 0 && !IsClosedDrawer(lnum)
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
  if IsContentClosed(lnum)
    if HasChildHeading(lnum, end)
      ShowChildren(lnum, end)
      return 'CHILDREN'
    endif
    OpenAll(lnum + 1, end)
    return 'SUBTREE'
  endif
  if HasClosedContent(lnum, end)
    OpenAll(lnum + 1, end)
    return 'SUBTREE'
  endif
  CloseContent(lnum)
  return 'FOLDED'
enddef

# TAB on the "… N lines" row of a closed fold opens it.
export def OpenClosed(lnum: number)
  var start = foldclosed(lnum)
  var end = foldclosedend(lnum)
  if IsClosedDrawer(lnum)
    execute 'silent! :' .. start .. 'foldopen'
  else
    OpenAll(start, end)
  endif
  cursor(start, 1)
enddef

def IsOverview(): bool
  var lnum = 1
  var last = line('$')
  while lnum <= last
    if Level(lnum) == 1
      var end = SubtreeEnd(lnum)
      if end > lnum && !IsContentClosed(lnum)
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
  var lnum = line('$')
  while lnum >= 1
    if Level(lnum) > 0
      # A leaf closes whole, and a parent stays open to show its children.
      if !HasChildHeading(lnum, SubtreeEnd(lnum))
        CloseContent(lnum)
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
  elseif HasClosedContent(0, line('$'))
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
