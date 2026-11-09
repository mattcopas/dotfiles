vim9script
# A fuzzy picker in a popup, built on matchfuzzypos(), so it needs no external finder.
#
# Pick() takes `title` and either `items` (a list of {text, ...}) or `Search`, a function
# called with (query, Append, Done) that returns a job to stop when the query changes.
# It returns {item, items, action}, where action is 'open' or 'quickfix', or {}.

const SELECTED_PROP = 'orgflowPickerSelected'
const MATCH_PROP = 'orgflowPickerMatch'
const PROMPT_PROP = 'orgflowPickerPrompt'
const SEARCH_DELAY = 0.12
const RESULT_LIMIT = 2000

def EnsureProps()
  if empty(prop_type_get(MATCH_PROP))
    prop_type_add(MATCH_PROP, {highlight: 'OrgflowPickerMatch', priority: 2, combine: true})
    prop_type_add(SELECTED_PROP, {highlight: 'OrgflowPickerSelected', priority: 1, combine: true})
    prop_type_add(PROMPT_PROP, {highlight: 'OrgflowPickerPrompt'})
  endif
enddef

def Clip(text: string, width: number): string
  if strwidth(text) <= width
    return text .. repeat(' ', width - strwidth(text))
  endif
  var clipped = text
  while strwidth(clipped) > width
    clipped = strcharpart(clipped, 0, strcharlen(clipped) - 1)
  endwhile
  return clipped .. repeat(' ', width - strwidth(clipped))
enddef

def Lines(view: dict<any>, width: number, height: number): list<any>
  var total = len(view.items)
  var prompt = '> ' .. view.query
  var busy = view.busy ? ' …' : ''
  var counter = printf('%d%s', total, busy)
  var gap = max([1, width - strwidth(prompt) - strwidth(counter)])
  var lines: list<any> = [{
    text: prompt .. repeat(' ', gap) .. counter,
    props: [{col: 1, length: 2, type: PROMPT_PROP}],
  }]
  var first = max([0, view.index - height + 1])
  var at = first
  while at < total && at < first + height
    var text = Clip(view.items[at].text, width)
    var props: list<any> = []
    if at == view.index
      add(props, {col: 1, length: strlen(text), type: SELECTED_PROP})
    endif
    if at < len(view.positions)
      for position in view.positions[at]
        var byte = byteidx(text, position)
        if byte >= 0 && byte < strlen(text)
          add(props, {col: byte + 1, length: strlen(strcharpart(text, position, 1)), type: MATCH_PROP})
        endif
      endfor
    endif
    add(lines, {text: text, props: props})
    at += 1
  endwhile
  return lines
enddef

def Filter(view: dict<any>, source: list<dict<any>>)
  if view.query ==# ''
    view.items = source
    view.positions = []
  else
    var found = matchfuzzypos(source, view.query, {key: 'text'})
    view.items = found[0]
    view.positions = found[1]
  endif
  view.index = 0
enddef

# Starts a search. Its callbacks check that they still belong to the latest search,
# because a stopped job can still deliver a last few lines.
def BeginSearch(view: dict<any>, opts: dict<any>): any
  var results: list<dict<any>> = []
  var token = {}
  view.token = token
  view.items = results
  view.positions = []
  view.index = 0
  view.busy = true
  var job = opts.Search(view.query, (item) => {
    if view.token is token && len(results) < RESULT_LIMIT
      add(results, item)
      view.changed = true
    endif
  }, () => {
    if view.token is token
      view.busy = false
      view.changed = true
    endif
  })
  return job
enddef

export def Pick(opts: dict<any>): dict<any>
  EnsureProps()
  var dynamic = has_key(opts, 'Search')
  var source: list<dict<any>> = get(opts, 'items', [])
  var width = max([40, min([&columns - 6, &columns * 4 / 5])])
  var height = max([3, min([&lines - 8, 14])])
  var view: dict<any> = {query: '', items: source, positions: [], index: 0, busy: false}
  var popup = popup_create(Lines(view, width, height), {
    title: ' ' .. opts.title .. ' ',
    pos: 'topleft',
    line: 2,
    col: (&columns - width) / 2,
    minwidth: width,
    maxwidth: width,
    minheight: height + 1,
    maxheight: height + 1,
    border: [],
    borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    highlight: 'OrgflowPicker',
    borderhighlight: ['OrgflowPickerBorder'],
    wrap: false,
    scrollbar: 0,
    zindex: 250,
  })
  var job: any = v:none
  var searchDue: any = v:none
  var dirty = false
  redraw

  var StopJob = () => {
    if type(job) == v:t_job && job_status(job) ==# 'run'
      job_stop(job)
    endif
    job = v:none
  }

  try
    while true
      if get(view, 'changed', false)
        view.changed = false
        dirty = true
      endif
      if dirty && getcharstr(1) ==# ''
        popup_settext(popup, Lines(view, width, height))
        redraw
        dirty = false
      endif
      var key = getcharstr(0)
      if key ==# ''
        if dynamic && type(searchDue) != v:t_none && reltimefloat(reltime(searchDue)) >= SEARCH_DELAY
          searchDue = v:none
          StopJob()
          job = BeginSearch(view, opts)
          dirty = true
        endif
        sleep 15m
        continue
      endif

      if key ==# "\<Esc>" || key ==# "\<C-g>" || key ==# "\<C-c>"
        return {}
      elseif key ==# "\<CR>"
        return view.index < len(view.items)
          ? {item: view.items[view.index], items: view.items, action: 'open'}
          : {}
      elseif key ==# "\<C-q>"
        return empty(view.items) ? {} : {item: view.items[view.index], items: view.items, action: 'quickfix'}
      elseif key ==# "\<Down>" || key ==# "\<C-n>" || key ==# "\<C-j>"
        view.index = empty(view.items) ? 0 : (view.index + 1) % len(view.items)
      elseif key ==# "\<Up>" || key ==# "\<C-p>" || key ==# "\<C-k>"
        view.index = empty(view.items) ? 0 : (view.index + len(view.items) - 1) % len(view.items)
      else
        var before: string = view.query
        if key ==# "\<BS>" || key ==# "\<C-h>"
          view.query = strcharpart(before, 0, strcharlen(before) - 1)
        elseif key ==# "\<C-u>"
          view.query = ''
        elseif key ==# "\<C-w>"
          view.query = substitute(before, '\S*\s*$', '', '')
        elseif strpart(key, 0, 1) !=# "\x80" && key !~# '^[[:cntrl:]]'
          view.query = before .. key
        endif
        if view.query !=# before
          if dynamic
            searchDue = reltime()
            if view.query ==# ''
              StopJob()
              searchDue = v:none
              view.token = {}
              view.items = []
              view.index = 0
              view.busy = false
            endif
          else
            Filter(view, source)
          endif
        endif
      endif
      dirty = true
    endwhile
  finally
    StopJob()
    popup_close(popup)
    redraw
  endtry
  return {}
enddef
