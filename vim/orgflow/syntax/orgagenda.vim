vim9script
# Agenda buffers, whose layout comes from agenda.vim.
import autoload 'orgflow/config.vim'

if exists('b:current_syntax')
  finish
endif

syntax case match

syntax match orgAgendaHeader /^\S.*$/ contains=NONE
syntax match orgAgendaDay /^\%(Monday\|Tuesday\|Wednesday\|Thursday\|Friday\|Saturday\|Sunday\) .*$/
syntax match orgAgendaSeparator /^=\+$/
syntax match orgAgendaGrid /^ \{14}\s*\d\{1,2}:\d\{2}\.\{6} -\{16}$/
syntax match orgAgendaNow /^ \{14}\s*\d\{1,2}:\d\{2}\.\{6} now .*$/
syntax match orgAgendaCategory /^  \S\{-}:\ze\s/ contained
syntax match orgAgendaItem /^  \S.*$/ contains=orgAgendaCategory,orgAgendaDeadline,orgAgendaScheduled,orgAgendaOverdue,orgAgendaTime,orgAgendaTags,orgAgendaTodo,orgAgendaActive,orgAgendaWait,orgAgendaDone,orgAgendaPriority
syntax match orgAgendaDeadline /\<Deadline:\|\<In \+\d\+ d\.:/ contained
syntax match orgAgendaOverdue /\d\+ d\. ago:\|Sched\. *\d\+x:/ contained
syntax match orgAgendaScheduled /\<Scheduled:/ contained
syntax match orgAgendaTime /\s\zs\d\{1,2}:\d\{2}\%(\.\{6}\|-\d\{1,2}:\d\{2}\)/ contained
syntax match orgAgendaTags /\s\zs:[[:alnum:]_@#%:]\+:$/ contained
syntax match orgAgendaPriority /\[#[A-Z0-9]\+\]/ contained

def Class(name: string, done: bool): string
  if done
    return 'orgAgendaDone'
  endif
  if name =~# '^\(IN PROGRESS\|IN REVIEW\|STRT\|\[-\]\)$'
    return 'orgAgendaActive'
  endif
  if name =~# '^\(WAIT\|HOLD\|\[?\]\)$'
    return 'orgAgendaWait'
  endif
  return 'orgAgendaTodo'
enddef

for sequence in config.OrgConfig().sequences
  for name in sequence.todo
    execute printf('syntax match %s /\s\zs%s\ze\s/ contained', Class(name, false), escape(name, '\/.*$^~[]'))
  endfor
  for name in sequence.done
    execute printf('syntax match %s /\s\zs%s\ze\s/ contained', Class(name, true), escape(name, '\/.*$^~[]'))
  endfor
endfor

highlight default link orgAgendaHeader Title
highlight default link orgAgendaDay Identifier
highlight default link orgAgendaSeparator Comment
highlight default link orgAgendaGrid Comment
highlight default link orgAgendaNow WarningMsg
highlight default link orgAgendaCategory Comment
highlight default link orgAgendaDeadline Error
highlight default link orgAgendaOverdue WarningMsg
highlight default link orgAgendaScheduled Type
highlight default link orgAgendaTime Constant
highlight default link orgAgendaTags Comment
highlight default link orgAgendaPriority Special
highlight default link orgAgendaTodo Todo
highlight default link orgAgendaActive WarningMsg
highlight default link orgAgendaWait Type
highlight default link orgAgendaDone Comment

b:current_syntax = 'orgagenda'
