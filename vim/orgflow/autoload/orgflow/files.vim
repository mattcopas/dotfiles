vim9script
# Reading and changing org files. Lines are text split on newlines, so a final newline
# shows as a final empty element and is kept. Unsaved work in a buffer is never
# overwritten: that buffer is edited in place and the save stays yours. Anything else
# goes straight to disk, keeping the file's line endings.

# The loaded buffer for a path, or 0.
export def BufferFor(path: string): number
  var wanted = resolve(path)
  for info in getbufinfo({bufloaded: 1})
    if info.name !=# '' && resolve(info.name) ==# wanted
      return info.bufnr
    endif
  endfor
  return 0
enddef

export def BufferLines(bufnr: number): list<string>
  var lines = getbufline(bufnr, 1, '$')
  if lines == ['']
    return lines
  endif
  return getbufvar(bufnr, '&endofline') ? lines + [''] : lines
enddef

# Changes only the lines that differ, so marks, folds and undo stay useful.
export def ApplyToBuffer(bufnr: number, wanted: list<string>)
  var finalNewline = len(wanted) > 1 && wanted[-1] ==# ''
  var after = finalNewline ? slice(wanted, 0, len(wanted) - 1) : wanted
  var before = getbufline(bufnr, 1, '$')
  var start = 0
  var limit = min([len(before), len(after)])
  while start < limit && before[start] ==# after[start]
    start += 1
  endwhile
  var endBefore = len(before)
  var endAfter = len(after)
  while endBefore > start && endAfter > start && before[endBefore - 1] ==# after[endAfter - 1]
    endBefore -= 1
    endAfter -= 1
  endwhile
  var at = start
  while at < endBefore && at < endAfter
    setbufline(bufnr, at + 1, after[at])
    at += 1
  endwhile
  if at < endAfter
    appendbufline(bufnr, at, slice(after, at, endAfter))
  elseif at < endBefore
    deletebufline(bufnr, at + 1, endBefore)
  endif
  if len(wanted) > 1 && getbufvar(bufnr, '&endofline') != finalNewline
    setbufvar(bufnr, '&endofline', finalNewline)
  endif
enddef

# A file's current lines. Unsaved buffer contents win, but a clean buffer is read from
# disk, so a `git pull` behind an open file can't be undone by saving old text over it.
# Returns {lines, exists}. A file that doesn't exist reads as [''].
export def Read(path: string): dict<any>
  var bufnr = BufferFor(path)
  if bufnr > 0 && getbufvar(bufnr, '&modified')
    return {lines: BufferLines(bufnr), exists: true}
  endif
  if !filereadable(path)
    return bufnr > 0
      ? {lines: BufferLines(bufnr), exists: true}
      : {lines: [''], exists: false}
  endif
  var lines = readfile(path, 'b')
  if empty(lines)
    return {lines: [''], exists: true}
  endif
  return {lines: map(lines, (_, line) => substitute(line, '\r$', '', '')), exists: true}
enddef

export def Write(path: string, lines: list<string>)
  var bufnr = BufferFor(path)
  if bufnr > 0 && getbufvar(bufnr, '&modified')
    ApplyToBuffer(bufnr, lines)
    return
  endif
  var crlf = false
  if filereadable(path)
    var existing = readfile(path, 'b', 1)
    crlf = !empty(existing) && existing[0] =~# '\r$'
  elseif bufnr > 0
    crlf = getbufvar(bufnr, '&fileformat') ==# 'dos'
  else
    mkdir(fnamemodify(path, ':h'), 'p')
  endif
  var total = len(lines)
  var out = crlf
    ? mapnew(lines, (i, line) => i < total - 1 ? line .. "\r" : line)
    : lines
  if writefile(out, path, 'b') != 0
    throw 'Couldn''t write ' .. path
  endif
  if bufnr > 0
    # Have Vim reload it now, with no prompt, because this change was ours.
    setbufvar(bufnr, '&autoread', 1)
    silent! execute 'checktime' bufnr
    # A change of the same size within the same instant can look like no change.
    if BufferLines(bufnr) != lines
      ApplyToBuffer(bufnr, lines)
      setbufvar(bufnr, '&modified', 0)
    endif
  endif
enddef

# Opens a file in this window, checking that a clean buffer isn't behind the disk.
export def Open(path: string)
  execute 'hide edit' fnameescape(path)
  silent! checktime
enddef

# Puts the cursor on a 0-based line, opening any folds around it.
export def Reveal(line: number, column: number = 0)
  cursor(line + 1, column + 1)
  silent! normal! zv
enddef

export def Warn(message: any)
  echohl WarningMsg
  echomsg 'Orgflow: ' .. message
  echohl None
enddef
