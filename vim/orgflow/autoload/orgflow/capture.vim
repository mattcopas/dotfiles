vim9script
# org-capture: pick a template with single keys, type a title, and the entry goes to
# its file and headline without leaving what you were doing.
import './agendaview.vim'
import './config.vim'
import './date.vim'
import './edits.vim'
import './files.vim'
import './menu.vim'
import './timestamp.vim' as ts

# The same work as Capture() below, once the template and title are known.
export def CaptureTo(template: dict<any>, title: string)
  var spec: dict<any> = {
    headline: template.headline,
    prepend: get(template, 'prepend', false),
    entry: 'TODO ' .. title,
  }
  var schedule: string = get(template, 'schedule', '')
  if schedule !=# ''
    var parsed = ts.ParseDateInput(schedule, date.Now().today)
    if empty(parsed)
      files.Warn(printf('Template %s: can''t read the date "%s"', template.key, schedule))
      return
    endif
    # The trailing space and indented line match what the org-capture template writes.
    spec.entry = 'TODO ' .. title .. ' '
    spec.extraLines = [' SCHEDULED: ' .. ts.FormatStamp(parsed.abs, parsed.minutes)]
  endif
  var path = config.Expand(template.file)
  var result = edits.CaptureEntry(files.Read(path).lines, spec, config.OrgConfig())
  files.Write(path, result.lines)
  agendaview.RefreshAll()
  redraw
  echo 'Captured to ' .. template.file
enddef

export def Capture(key: string = '')
  var templates: list<dict<any>> = config.Get('capture.templates')
  var chosen: dict<any> = {}
  if key !=# ''
    var found = filter(copy(templates), (_, t) => t.key ==# key)
    if empty(found) || !has_key(found[0], 'file')
      files.Warn(printf('No capture template "%s"', key))
      return
    endif
    chosen = found[0]
  else
    var node = menu.Pick(menu.TreeFromKeys(templates, (t) => has_key(t, 'file')), 'Capture')
    if empty(node)
      return
    endif
    chosen = node.value
  endif
  var title = input(chosen.description .. ': ')
  if title ==# ''
    return
  endif
  try
    CaptureTo(chosen, title)
  catch
    files.Warn(v:exception)
  endtry
enddef
