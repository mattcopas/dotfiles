vim9script
# Org table alignment and cell movement. Formulas are out of scope: a #+TBLFM line is
# left untouched and nothing is recalculated. Columns are byte offsets from 0, which is
# what Vim's cursor uses, and widths are display cells, so wide characters still line up.

export def IsTableLine(line: string): bool
  return line =~# '^\s*|'
enddef

def IsRule(line: string): bool
  return line =~# '^\s*|-'
enddef

export def TableBounds(lines: list<string>, line: number): dict<number>
  var start = line
  while start > 0 && IsTableLine(lines[start - 1])
    start -= 1
  endwhile
  var end = line + 1
  while end < len(lines) && IsTableLine(lines[end])
    end += 1
  endwhile
  return {start: start, end: end}
enddef

def Cells(line: string): list<string>
  var body = substitute(trim(line), '^|', '', '')
  body = substitute(body, '|\s*$', '', '')
  return mapnew(split(body, '|', 1), (_, cell) => trim(cell))
enddef

const NUMERIC = '\C\v^%([\>\<]?[-+]?[0-9.,]+[eE]?[-+]?[0-9]*\%?|[\<\>]?[-+]?0[xX][0-9a-fA-F.]+|[\<\>]?[-+]?[0-9]+%([.,][0-9]*)?[-+]?[0-9]*[KMGTPkmgtp]?)$'

# Aligns one table, right-aligning columns that are mostly numbers, as org does.
export def AlignTable(lines: list<string>, start: number, end: number): list<string>
  var rows = slice(lines, start, end)
  var indent = matchstr(rows[0], '^\s*')
  var parsed: list<any> = []
  var columns = 0
  for row in rows
    if IsRule(row)
      add(parsed, v:none)
    else
      var cells = Cells(row)
      add(parsed, cells)
      columns = max([columns, len(cells)])
    endif
  endfor
  var widths: list<number> = repeat([1], columns)
  var numbers: list<number> = repeat([0], columns)
  var filled: list<number> = repeat([0], columns)
  for row in parsed
    if type(row) != v:t_list
      continue
    endif
    var i = 0
    for cell in row
      widths[i] = max([widths[i], strwidth(cell)])
      if cell !=# ''
        filled[i] += 1
        if cell =~# NUMERIC
          numbers[i] += 1
        endif
      endif
      i += 1
    endfor
  endfor
  var rule = indent .. '|' .. join(mapnew(widths, (_, w) => repeat('-', w + 2)), '+') .. '|'
  var out: list<string> = []
  for row in parsed
    if type(row) != v:t_list
      add(out, rule)
      continue
    endif
    var cells: list<string> = []
    var i = 0
    while i < columns
      var cell: string = get(row, i, '')
      var pad = repeat(' ', widths[i] - strwidth(cell))
      var right = filled[i] > 0 && numbers[i] * 2 > filled[i]
      add(cells, ' ' .. (right ? pad .. cell : cell .. pad) .. ' ')
      i += 1
    endwhile
    add(out, indent .. '|' .. join(cells, '|') .. '|')
  endfor
  return out
enddef

export def AlignTableAt(input: list<string>, line: number): list<string>
  if line >= len(input) || !IsTableLine(input[line])
    return input
  endif
  var bounds = TableBounds(input, line)
  return slice(input, 0, bounds.start) + AlignTable(input, bounds.start, bounds.end) + slice(input, bounds.end)
enddef

def CellStarts(line: string): list<number>
  var starts: list<number> = []
  var last = strlen(trim(line, '', 2)) - 1
  var at = stridx(line, '|')
  while at >= 0 && at < last
    add(starts, strpart(line, at + 1, 1) ==# ' ' ? at + 2 : at + 1)
    at = stridx(line, '|', at + 1)
  endwhile
  return starts
enddef

# The next cell after a column, skipping horizontal rules. Reaching the end of the
# table means a new row is needed, reported with `addRow`.
export def NextCell(lines: list<string>, line: number, column: number): dict<any>
  var onRow = filter(CellStarts(lines[line]), (_, start) => start > column)
  if !IsRule(lines[line]) && !empty(onRow)
    return {line: line, column: onRow[0], addRow: false}
  endif
  var at = line + 1
  while at < len(lines) && IsRule(lines[at])
    at += 1
  endwhile
  if at < len(lines) && IsTableLine(lines[at])
    return {line: at, column: get(CellStarts(lines[at]), 0, 0), addRow: false}
  endif
  return {line: at, column: 0, addRow: true}
enddef

# An empty row shaped like the row above it.
export def BlankRow(line: string): string
  return substitute(line, '[^| \t]', ' ', 'g')
enddef
