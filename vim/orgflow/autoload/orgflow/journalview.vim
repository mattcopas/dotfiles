vim9script
# org-journal-new-entry: open this month's file, carry unfinished items over from the
# most recent earlier day, and start a timed entry.
import './config.vim'
import './date.vim'
import './files.vim'
import './journal.vim'

# The newest journal file other than today's that has a day before today, or {}.
def PreviousFile(directory: string, currentName: string, today: number, cfg: dict<any>): dict<any>
  if !isdirectory(directory)
    return {}
  endif
  var dated: list<dict<any>> = []
  for name in readdir(directory)
    var month = journal.FileNameToMonth(name, cfg)
    if month >= 0 && name !=# currentName && month <= today
      add(dated, {name: name, month: month})
    endif
  endfor
  sort(dated, (a, b) => b.month - a.month)
  for entry in dated
    var path = directory .. '/' .. entry.name
    var file = files.Read(path)
    if file.exists && journal.LatestDayBefore(file.lines, today, config.OrgConfig()) >= 0
      return {path: path, lines: file.lines}
    endif
  endfor
  return {}
enddef

export def NewEntry()
  try
    var clock = date.Now()
    var directory = substitute(config.Expand(config.Get('journal.directory')), '/$', '', '')
    var cfg = config.JournalConfig()
    var name = journal.JournalFileName(clock.today, cfg)
    var path = directory .. '/' .. name
    var current = files.Read(path).lines
    var input: dict<any> = {clock: clock, config: cfg, orgConfig: config.OrgConfig(), currentLines: current}
    var donor: dict<any> = {}
    if journal.LatestDayBefore(current, clock.today, config.OrgConfig()) < 0
      donor = PreviousFile(directory, name, clock.today, cfg)
      if !empty(donor)
        input.previousLines = donor.lines
      endif
    endif
    var plan = journal.PlanNewEntry(input)
    files.Write(path, plan.current)
    if !empty(donor) && !empty(plan.previous)
      files.Write(donor.path, plan.previous)
    endif
    files.Open(path)
    files.Reveal(plan.line)
    normal! $
  catch
    files.Warn(v:exception)
  endtry
enddef
