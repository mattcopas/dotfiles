vim9script
# Project switching and search, following your project.el setup. Switching changes
# Vim's working directory and goes straight to find-file, and your other buffers stay
# open, which is closer to Emacs than VS Code's one project per window.
import './config.vim'
import './files.vim'
import './picker.vim'

const SKIP = ['node_modules', 'target', 'build', 'dist', 'vendor', 'elpaca', '__pycache__']
const MAX_DEPTH = 4
const RECENT_LIMIT = 100

def IsRepository(path: string): bool
  return isdirectory(path .. '/.git') || filereadable(path .. '/.git')
enddef

def Visit(path: string, recursive: bool, depth: number, found: list<string>)
  if !isdirectory(path)
    return
  endif
  if IsRepository(path)
    add(found, path)
    return
  endif
  if depth >= MAX_DEPTH
    return
  endif
  var names: list<string> = []
  try
    names = readdir(path, (name) => name !~# '^\.' && index(SKIP, name) < 0)
  catch
    return
  endtry
  for name in names
    var child = substitute(path, '/$', '', '') .. '/' .. name
    if !isdirectory(child)
      continue
    endif
    if recursive
      Visit(child, true, depth + 1, found)
    elseif IsRepository(child)
      add(found, child)
    endif
  endfor
enddef

export def DiscoverProjects(roots: list<any>): list<string>
  var found: list<string> = []
  for root in roots
    var isString = type(root) == v:t_string
    var path = config.Expand(isString ? root : root.path)
    Visit(path, isString ? false : get(root, 'recursive', false), 0, found)
  endfor
  return uniq(sort(found))
enddef

# Most recently used first, then alphabetical.
export def SortProjects(projects: list<string>, recent: list<string>): list<string>
  var used = filter(copy(recent), (_, p) => index(projects, p) >= 0)
  var others = filter(copy(projects), (_, p) => index(used, p) < 0)
  return used + others
enddef

def StateFile(): string
  var base = $XDG_STATE_HOME !=# '' ? $XDG_STATE_HOME : $HOME .. '/.local/state'
  return base .. '/orgflow/vim-projects.json'
enddef

def RecentProjects(): list<string>
  var path = StateFile()
  if !filereadable(path)
    return []
  endif
  try
    return json_decode(join(readfile(path), "\n"))
  catch
    return []
  endtry
enddef

export def Remember(path: string)
  var recent = [path] + filter(RecentProjects(), (_, p) => p !=# path)
  var file = StateFile()
  mkdir(fnamemodify(file, ':h'), 'p')
  writefile([json_encode(slice(recent, 0, RECENT_LIMIT))], file)
enddef

def Display(path: string): string
  var home = $HOME .. '/'
  return strpart(path, 0, strlen(home)) ==# home ? '~/' .. strpart(path, strlen(home)) : path
enddef

# The nearest repository above the current file, or the working directory.
export def ProjectRoot(): string
  var start = &buftype ==# '' && expand('%:p') !=# '' ? expand('%:p:h') : getcwd()
  var dir = start
  while true
    if IsRepository(dir)
      return dir
    endif
    var parent = fnamemodify(dir, ':h')
    if parent ==# dir
      return getcwd()
    endif
    dir = parent
  endwhile
  return getcwd()
enddef

export def ListFiles(root: string): list<string>
  var quoted = shellescape(root)
  if IsRepository(root) && executable('git') == 1
    var tracked = systemlist('git -C ' .. quoted .. ' ls-files --cached --others --exclude-standard')
    if v:shell_error == 0
      return uniq(sort(tracked))
    endif
  endif
  if executable('rg') == 1
    return systemlist('cd ' .. quoted .. ' && rg --files')
  endif
  return map(systemlist('cd ' .. quoted .. ' && find . -type f -not -path "*/.*"'), (_, f) => substitute(f, '^\./', '', ''))
enddef

def OpenResult(root: string, name: string)
  files.Open(name =~# '^/' ? name : root .. '/' .. name)
enddef

export def FindFile()
  var root = ProjectRoot()
  var names = ListFiles(root)
  var chosen = picker.Pick({
    title: 'Find file: ' .. Display(root),
    items: mapnew(names, (_, name) => ({text: name})),
  })
  if !empty(chosen)
    OpenResult(root, chosen.item.text)
  endif
enddef

export def SwitchProject()
  var found = DiscoverProjects(config.Get('projects.roots'))
  var ordered = SortProjects(found, RecentProjects())
  var chosen = picker.Pick({
    title: 'Switch to project',
    items: mapnew(ordered, (_, path) => ({
      text: printf('%-28s %s', fnamemodify(path, ':t'), Display(path)),
      path: path,
    })),
  })
  if empty(chosen)
    return
  endif
  Remember(chosen.item.path)
  execute 'cd' fnameescape(chosen.item.path)
  # Keep find-file in the new project even when the current file is somewhere else.
  var names = ListFiles(chosen.item.path)
  var next = picker.Pick({
    title: 'Find file: ' .. Display(chosen.item.path),
    items: mapnew(names, (_, name) => ({text: name})),
  })
  if !empty(next)
    OpenResult(chosen.item.path, next.item.text)
  endif
enddef

def GrepCommand(query: string): list<string>
  if executable('rg') == 1
    return ['rg', '--vimgrep', '--smart-case', '--color=never', '--max-columns=300', '--', query]
  endif
  if executable('git') == 1
    return ['git', 'grep', '-n', '--column', '-I', '-i', '-e', query]
  endif
  return ['grep', '-rnI', '-i', '--', query, '.']
enddef

def ParseResult(root: string, line: string): dict<any>
  var m = matchlist(line, '\C\v^(.{-}):(\d+):%((\d+):)?(.*)$')
  if empty(m)
    return {text: line}
  endif
  var column = m[3] ==# '' ? 1 : str2nr(m[3])
  return {
    text: printf('%s:%s: %s', m[1], m[2], trim(m[4])),
    filename: m[1] =~# '^/' ? m[1] : root .. '/' .. m[1],
    lnum: str2nr(m[2]),
    col: column,
  }
enddef

def ToQuickfix(items: list<dict<any>>, title: string)
  var entries = filter(copy(items), (_, item) => has_key(item, 'filename'))
  setqflist([], ' ', {
    title: title,
    items: mapnew(entries, (_, item) => ({
      filename: item.filename,
      lnum: item.lnum,
      col: item.col,
      text: item.text,
    })),
  })
  copen
enddef

export def SearchProject()
  var root = ProjectRoot()
  var chosen = picker.Pick({
    title: 'Search: ' .. Display(root),
    Search: (query, Append, Done) => job_start(GrepCommand(query), {
      cwd: root,
      in_io: 'null',
      err_io: 'null',
      out_mode: 'nl',
      out_cb: (_, line) => Append(ParseResult(root, line)),
      exit_cb: (_, _) => Done(),
    }),
  })
  if empty(chosen)
    return
  endif
  if chosen.action ==# 'quickfix'
    ToQuickfix(chosen.items, 'Search: ' .. root)
    return
  endif
  if has_key(chosen.item, 'filename')
    files.Open(chosen.item.filename)
    files.Reveal(chosen.item.lnum - 1, chosen.item.col - 1)
  endif
enddef

export def Grep()
  var query = input('Search project: ')
  if query ==# ''
    return
  endif
  var root = ProjectRoot()
  var command = join(mapnew(GrepCommand(query), (_, part) => shellescape(part)), ' ')
  var lines = systemlist('cd ' .. shellescape(root) .. ' && ' .. command)
  ToQuickfix(mapnew(lines, (_, line) => ParseResult(root, line)), 'Search: ' .. query)
enddef

export def Buffers()
  var infos = filter(getbufinfo({buflisted: 1}), (_, b) => b.bufnr != bufnr() && b.name !=# '')
  sort(infos, (a, b) => b.lastused - a.lastused)
  var chosen = picker.Pick({
    title: 'Switch buffer',
    items: mapnew(infos, (_, b) => ({text: Display(b.name), bufnr: b.bufnr})),
  })
  if !empty(chosen)
    execute 'hide buffer' chosen.item.bufnr
  endif
enddef

export def ProjectBuffers()
  var root = ProjectRoot() .. '/'
  var infos = filter(getbufinfo({buflisted: 1}), (_, b) => strpart(b.name, 0, strlen(root)) ==# root && b.bufnr != bufnr())
  sort(infos, (a, b) => b.lastused - a.lastused)
  var chosen = picker.Pick({
    title: 'Project buffers',
    items: mapnew(infos, (_, b) => ({text: strpart(b.name, strlen(root)), bufnr: b.bufnr})),
  })
  if !empty(chosen)
    execute 'hide buffer' chosen.item.bufnr
  endif
enddef

export def KillBuffer()
  var bufnr = bufnr()
  if getbufvar(bufnr, '&modified') && confirm('Discard unsaved changes in this buffer?', "&Yes\n&No", 2) != 1
    return
  endif
  var alternate = bufnr('#')
  if alternate > 0 && alternate != bufnr && buflisted(alternate) == 1
    execute 'hide buffer' alternate
  else
    hide enew
  endif
  execute 'bwipeout!' bufnr
enddef

export def KillProjectBuffers()
  var root = ProjectRoot() .. '/'
  var infos = filter(getbufinfo({buflisted: 1}), (_, b) => strpart(b.name, 0, strlen(root)) ==# root)
  if empty(infos)
    return
  endif
  var dirty = len(filter(copy(infos), (_, b) => b.changed == 1))
  var question = printf('Close %d project buffers%s?', len(infos), dirty > 0 ? printf(', %d with unsaved changes', dirty) : '')
  if confirm(question, "&Yes\n&No", 2) != 1
    return
  endif
  for info in infos
    execute 'bwipeout!' info.bufnr
  endfor
enddef

export def Revert()
  if &modified && confirm('Discard unsaved changes in this buffer?', "&Yes\n&No", 2) != 1
    return
  endif
  edit!
enddef

export def OpenFile()
  var start = expand('%:p:h')
  var path = input('Find file: ', (start ==# '' ? getcwd() : start) .. '/', 'file')
  if path !=# ''
    files.Open(fnamemodify(path, ':p'))
  endif
enddef

export def Recent()
  var names = filter(copy(v:oldfiles), (_, f) => filereadable(expand(f)))
  var chosen = picker.Pick({
    title: 'Recent files',
    items: mapnew(names, (_, f) => ({text: f})),
  })
  if !empty(chosen)
    files.Open(expand(chosen.item.text))
  endif
enddef

export def SearchBuffer()
  var chosen = picker.Pick({
    title: 'Search buffer',
    items: mapnew(getline(1, '$'), (i, text) => ({text: printf('%5d  %s', i + 1, text), lnum: i + 1})),
  })
  if !empty(chosen)
    files.Reveal(chosen.item.lnum - 1)
  endif
enddef

export def Git()
  if exists(':Git') == 2
    execute 'Git'
    return
  endif
  files.Warn('vim-fugitive isn''t installed. See "Git" in the Orgflow README.')
enddef
