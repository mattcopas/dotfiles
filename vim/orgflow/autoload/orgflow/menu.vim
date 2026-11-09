vim9script
# which-key: a key tree with the next level shown in a popup. Keys are read directly,
# so anything typed before the popup appears is simply the next key in the sequence.
#
# A node is {key, name} plus either `children` or `cmd` (an Ex command) or any other
# data the caller wants back. `filetypes` limits a node to those filetypes.
import './config.vim'
import './files.vim'

const KEY_PROP = 'orgflowMenuKey'
const GROUP_PROP = 'orgflowMenuGroup'
const TITLE_PROP = 'orgflowMenuTitle'

def EnsureProps()
  for [name, group] in [[KEY_PROP, 'OrgflowMenuKey'], [GROUP_PROP, 'OrgflowMenuGroup'], [TITLE_PROP, 'OrgflowMenuTitle']]
    if empty(prop_type_get(name))
      prop_type_add(name, {highlight: group})
    endif
  endfor
enddef

def KeyLabel(key: string): string
  return key ==# ' ' ? 'SPC' : key
enddef

# Leaves out nodes for other filetypes, and groups left with nothing in them.
export def FilterTree(nodes: list<any>, filetype: string): list<any>
  var out: list<any> = []
  for node in nodes
    if has_key(node, 'filetypes') && index(node.filetypes, filetype) < 0
      continue
    endif
    if has_key(node, 'children')
      var children = FilterTree(node.children, filetype)
      if !empty(children)
        add(out, extendnew(node, {children: children}))
      endif
    else
      add(out, node)
    endif
  endfor
  return out
enddef

def Render(nodes: list<any>, crumbs: list<string>): list<any>
  var labels = mapnew(nodes, (_, node) => {
    var name: string = has_key(node, 'children') ? '+' .. node.name : node.name
    return {key: KeyLabel(node.key), name: name, group: has_key(node, 'children')}
  })
  var widest = max(mapnew(labels, (_, l) => strwidth(l.key) + strwidth(l.name))) + 6
  var columns = max([1, min([(&columns - 2) / widest, 6])])
  var count = len(labels)
  var rows = (count + columns - 1) / columns
  var title = join(crumbs, ' ')
  var lines: list<any> = [{
    text: ' ' .. title,
    props: [{col: 2, length: strlen(title), type: TITLE_PROP}],
  }]
  var row = 0
  while row < rows
    var text = ' '
    var props: list<any> = []
    var column = 0
    while column < columns
      var at = column * rows + row
      if at < count
        var label = labels[at]
        add(props, {col: strlen(text) + 1, length: strlen(label.key), type: KEY_PROP})
        text ..= label.key .. ' → '
        var nameAt = strlen(text) + 1
        if label.group
          add(props, {col: nameAt, length: strlen(label.name), type: GROUP_PROP})
        endif
        text ..= label.name
        var used = strwidth(label.key) + strwidth(label.name) + 3
        text ..= repeat(' ', widest - used)
      endif
      column += 1
    endwhile
    add(lines, {text: text, props: props})
    row += 1
  endwhile
  return lines
enddef

def ReadKey(nodes: list<any>, crumbs: list<string>, popup: number, delay: number): dict<any>
  var id = popup
  if id == 0
    var waited = 0
    while waited < delay
      var early = getcharstr(0)
      if early !=# ''
        return {key: early, popup: 0}
      endif
      sleep 10m
      waited += 10
    endwhile
    id = popup_create(Render(nodes, crumbs), {
      line: &lines - &cmdheight,
      col: 1,
      pos: 'botleft',
      minwidth: &columns,
      maxwidth: &columns,
      highlight: 'OrgflowMenu',
      wrap: false,
      zindex: 300,
    })
  else
    popup_settext(id, Render(nodes, crumbs))
  endif
  redraw
  return {key: getcharstr(), popup: id}
enddef

# Walks the tree one key at a time. Returns the chosen node, or {} when cancelled.
export def Pick(root: list<any>, title: string, delay: number = 0): dict<any>
  EnsureProps()
  var trail: list<any> = [root]
  var crumbs: list<string> = [title]
  var popup = 0
  try
    while true
      var nodes: list<any> = trail[-1]
      var read = ReadKey(nodes, crumbs, popup, delay)
      popup = read.popup
      var key: string = read.key
      if key ==# "\<Esc>" || key ==# "\<C-g>" || key ==# "\<C-c>"
        return {}
      endif
      if key ==# "\<BS>"
        if len(trail) > 1
          remove(trail, -1)
          remove(crumbs, -1)
        endif
        continue
      endif
      # Mouse and other non-text events aren't answers to the menu.
      if strpart(key, 0, 1) ==# "\x80"
        continue
      endif
      var found: dict<any> = {}
      for node in nodes
        if node.key ==# key
          found = node
          break
        endif
      endfor
      if empty(found)
        echo join(crumbs, ' ') .. ' ' .. KeyLabel(key) .. ' is undefined'
        return {}
      endif
      if !has_key(found, 'children')
        return found
      endif
      add(trail, found.children)
      add(crumbs, KeyLabel(found.key))
    endwhile
  finally
    if popup > 0
      popup_close(popup)
      redraw
    endif
  endtry
  return {}
enddef

# Builds a tree from flat keys such as `w`, `ww` and `wt`, where `w` is the group.
# IsLeaf decides what's selectable, and the original entry is returned as `value`.
export def TreeFromKeys(entries: list<dict<any>>, IsLeaf: func): list<any>
  var root: list<any> = []
  for entry in entries
    var path = split(entry.key, '\zs')
    var level = root
    for char in slice(path, 0, len(path) - 1)
      var group = filter(copy(level), (_, n) => n.key ==# char)
      if empty(group)
        var created: dict<any> = {key: char, name: char, children: []}
        add(level, created)
        level = created.children
      else
        level = group[0].children
      endif
    endfor
    var last = path[-1]
    var existing = filter(copy(level), (_, n) => n.key ==# last)
    if IsLeaf(entry)
      add(level, {key: last, name: entry.description, value: entry})
    elseif empty(existing)
      add(level, {key: last, name: entry.description, children: []})
    else
      existing[0].name = entry.description
    endif
  endfor
  return root
enddef

# The default SPC menu, following your Emacs bindings.
def DefaultMenu(): list<any>
  var org = ['org']
  var both = ['org', 'orgagenda']
  return [
    {key: ' ', name: 'Find file in project', cmd: 'OrgflowFindFile'},
    {key: 'w', name: 'Save file', cmd: 'write'},
    {key: 'X', name: 'Org capture', cmd: 'OrgCapture'},
    {key: 'b', name: 'buffer', children: [
      {key: 'b', name: 'Switch buffer', cmd: 'OrgflowBuffers'},
      {key: 'k', name: 'Kill buffer', cmd: 'OrgflowKillBuffer'},
      {key: 'r', name: 'Revert buffer', cmd: 'OrgflowRevert'},
      {key: 'n', name: 'Next buffer', cmd: 'hide bnext'},
      {key: 'p', name: 'Previous buffer', cmd: 'hide bprevious'},
    ]},
    {key: 'f', name: 'file', children: [
      {key: 'f', name: 'Find file', cmd: 'OrgflowOpenFile'},
      {key: 'r', name: 'Recent files', cmd: 'OrgflowRecent'},
      {key: 's', name: 'Save file', cmd: 'write'},
    ]},
    {key: 'g', name: 'git', children: [
      {key: 'g', name: 'Git status', cmd: 'OrgflowGit'},
      {key: 's', name: 'Git status', cmd: 'OrgflowGit'},
    ]},
    {key: 'n', name: 'notes', children: [
      {key: 'j', name: 'journal', children: [
        {key: 'j', name: 'New journal entry', cmd: 'OrgJournal'},
      ]},
    ]},
    {key: 'o', name: 'org', children: [
      {key: 'A', name: 'Agenda', cmd: 'OrgAgenda'},
      {key: 'l', name: 'Insert link', cmd: 'OrgLink', filetypes: org},
    ]},
    {key: 'p', name: 'project', children: [
      {key: 'p', name: 'Switch project', cmd: 'OrgflowSwitchProject'},
      {key: 'f', name: 'Find file in project', cmd: 'OrgflowFindFile'},
      {key: 'b', name: 'Project buffers', cmd: 'OrgflowProjectBuffers'},
      {key: 'k', name: 'Kill project buffers', cmd: 'OrgflowKillProjectBuffers'},
      {key: 'D', name: 'Project root', cmd: 'OrgflowProjectRoot'},
    ]},
    {key: 's', name: 'search', children: [
      {key: 's', name: 'Search buffer', cmd: 'OrgflowSearchBuffer'},
      {key: 'p', name: 'Search project', cmd: 'OrgflowSearchProject'},
      {key: 'P', name: 'Search project to quickfix', cmd: 'OrgflowGrep'},
      {key: 'o', name: 'Search headings', cmd: 'OrgHeadings', filetypes: org},
      {key: 'n', name: 'Clear search highlight', cmd: 'nohlsearch'},
      {key: 'c', name: 'Spell check', cmd: 'setlocal spell! spelllang=en'},
      {key: 'v', name: 'Reload vimrc', cmd: 'source $MYVIMRC'},
    ]},
    {key: 'v', name: 'vim', children: [
      {key: 'v', name: 'Edit vimrc', cmd: 'hide edit $MYVIMRC'},
    ]},
    {key: 'm', name: 'org local', filetypes: both, children: [
      {key: 't', name: 'todo', children: [
        {key: 't', name: 'Todo', cmd: 'OrgTodo TODO'},
        {key: 'p', name: 'In Progress', cmd: 'OrgTodo IN PROGRESS'},
        {key: 'w', name: 'In Review', cmd: 'OrgTodo IN REVIEW'},
        {key: 'W', name: 'Wait', cmd: 'OrgTodo WAIT'},
        {key: 'd', name: 'Done', cmd: 'OrgTodo DONE'},
        {key: 'm', name: 'Pick a state', cmd: 'OrgTodo'},
      ]},
      {key: 's', name: 'schedule', children: [
        {key: 't', name: 'Today', cmd: 'OrgSchedule +0d'},
        {key: 'T', name: 'Tomorrow', cmd: 'OrgSchedule +1d'},
        {key: 's', name: 'Pick a date', cmd: 'OrgSchedule'},
      ]},
      {key: 'd', name: 'Set deadline', cmd: 'OrgDeadline'},
      {key: 'q', name: 'Set tags', cmd: 'OrgTags', filetypes: org},
      {key: 'a', name: 'Align table', cmd: 'OrgAlign', filetypes: org},
    ]},
  ]
enddef

export def Open()
  var tree: list<any> = config.Get('vim.menu', DefaultMenu())
  var node = Pick(FilterTree(tree, &filetype), 'SPC', config.Get('whichKey.delay', 700))
  if empty(node)
    return
  endif
  try
    execute node.cmd
  catch
    files.Warn(v:exception)
  endtry
enddef
