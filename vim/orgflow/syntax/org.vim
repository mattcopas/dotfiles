vim9script
# Org highlighting. Markers hide through conceal, except on the cursor line, so a line
# shows its real text as soon as you're on it.
import autoload 'orgflow/config.vim'

if exists('b:current_syntax')
  finish
endif

syntax case match
syntax sync fromstart

def EscapeWord(word: string): string
  return escape(word, '\/.*$^~[]')
enddef

# Headings. Everything else on a heading line is contained inside these.
const INSIDE = 'orgStars,orgKeywordTodo,orgKeywordActive,orgKeywordWait,orgKeywordDone,orgPriority,orgTags,orgLink,orgLinkPlain,orgBareUrl,orgBold,orgItalic,orgUnderline,orgStrike,orgVerbatim,orgCode,orgTimestamp'
var level = 1
while level <= 8
  var stars = level == 8 ? '\*\{8,}' : '\*\{' .. level .. '}'
  execute printf('syntax match orgHeading%d /^%s .*$/ contains=%s', level, stars, INSIDE)
  level += 1
endwhile

# Leading stars become blanks, keeping the indentation, as org-hide-leading-stars does.
syntax match orgStars /^\*\+ /me=e-1 contained contains=orgLeadingStars
syntax match orgLeadingStars /^\*\+\ze\*/ conceal cchar=  contained

# Keyword classes follow Doom: active work, then blocked work, then finished work.
def KeywordClass(name: string, done: bool): string
  if done
    return 'orgKeywordDone'
  endif
  if name =~# '^\(IN PROGRESS\|IN REVIEW\|STRT\|\[-\]\)$'
    return 'orgKeywordActive'
  endif
  if name =~# '^\(WAIT\|HOLD\|\[?\]\)$'
    return 'orgKeywordWait'
  endif
  return 'orgKeywordTodo'
enddef

for sequence in config.OrgConfig().sequences
  for name in sequence.todo
    execute printf('syntax match %s /\%%(^\*\+ \)\@<=%s\%%( \|$\)\@=/ contained', KeywordClass(name, false), EscapeWord(name))
  endfor
  for name in sequence.done
    execute printf('syntax match %s /\%%(^\*\+ \)\@<=%s\%%( \|$\)\@=/ contained', KeywordClass(name, true), EscapeWord(name))
  endfor
endfor

syntax match orgPriority /\[#[A-Z0-9]\+\]/ contained
syntax match orgTags /[ \t]\zs:[[:alnum:]_@#%:]\+:\ze[ \t]*$/ contained

# Emphasis only applies with org's own rules for what can sit around the markers.
const PRE = '\%(^\|[[:space:](''"{-]\)\zs'
const POST = '\ze\%($\|[[:space:].,:;!?''")}\]-]\)'
def Emphasis(group: string, marker: string)
  execute printf('syntax region %s matchgroup=orgMarker start=/%s%s\ze[^[:space:]*]/ end=/[^[:space:]]\zs%s%s/ oneline concealends', group, PRE, marker, marker, POST)
enddef
Emphasis('orgBold', '\*')
Emphasis('orgItalic', '\/')
Emphasis('orgUnderline', '_')
Emphasis('orgStrike', '+')
Emphasis('orgVerbatim', '=')
Emphasis('orgCode', '\~')

# Links show their description, or their target when that's all they have.
syntax match orgLink /\[\[[^]]\+\]\[[^]]*\]\]/ contains=orgLinkTarget,orgLinkEnd
syntax match orgLinkTarget /\[\[[^]]\+\]\[/ contained conceal
syntax match orgLinkEnd /\]\]/ contained conceal
syntax match orgLinkPlain /\[\[[^]]\+\]\]/ contains=orgLinkOpen,orgLinkEnd
syntax match orgLinkOpen /\[\[/ contained conceal
syntax match orgBareUrl /\<https\?:\/\/[^[:space:]\]>)]\+/

syntax match orgTimestamp /[<[]\d\{4}-\d\{2}-\d\{2}[^]>]*[]>]/
syntax match orgPlanning /^\s*\%(SCHEDULED\|DEADLINE\|CLOSED\):.*$/ contains=orgPlanningLabel,orgTimestamp
syntax match orgPlanningLabel /\%(SCHEDULED\|DEADLINE\|CLOSED\):/ contained

syntax match orgComment /^\s*#\%(\s.*\)\=$/
syntax match orgKeywordLine /^\s*#+[[:alnum:]_]\+:.*$/
syntax match orgDrawer /^\s*:[[:alnum:]_-]\+:\%(\s.*\)\=$/
syntax match orgTable /^\s*|.*$/
syntax match orgList /^\s*\%([-+]\|\d\+[.)]\)\s/

syntax case ignore
syntax region orgBlock matchgroup=orgBlockDelimiter start=/^\s*#+begin_\w\+.*$/ end=/^\s*#+end_\w\+\s*$/ keepend

# Source blocks use the real syntax for their language. Only languages in this file are
# loaded, because each one costs time.
const ALIASES: dict<string> = {
  bash: 'sh', shell: 'sh', zsh: 'zsh', js: 'javascript', ts: 'typescript',
  py: 'python', 'emacs-lisp': 'lisp', elisp: 'lisp', 'c++': 'cpp', yml: 'yaml',
}
def IncludeLanguages()
  var seen: dict<bool> = {}
  for line in getline(1, '$')
    var m = matchlist(line, '\c^\s*#+begin_src\s\+\([[:alnum:]_+-]\+\)')
    if empty(m) || has_key(seen, m[1])
      continue
    endif
    var name: string = m[1]
    seen[name] = true
    var language: string = get(ALIASES, tolower(name), tolower(name))
    if empty(globpath(&runtimepath, 'syntax/' .. language .. '.vim'))
      continue
    endif
    var cluster = 'orgSrcCluster' .. substitute(language, '[^[:alnum:]]', '', 'g')
    silent! unlet b:current_syntax
    try
      execute printf('syntax include @%s syntax/%s.vim', cluster, language)
    catch
      continue
    endtry
    unlet! b:current_syntax
    syntax case ignore
    execute printf('syntax region orgSrc%s matchgroup=orgBlockDelimiter start=/^\s*#+begin_src\s\+%s\>.*$/ end=/^\s*#+end_src\s*$/ keepend contains=@%s',
      substitute(language, '[^[:alnum:]]', '', 'g'), escape(name, '/+'), cluster)
  endfor
enddef
IncludeLanguages()
syntax case match

highlight default link orgHeading1 Title
highlight default link orgHeading2 Identifier
highlight default link orgHeading3 Function
highlight default link orgHeading4 Title
highlight default link orgHeading5 Identifier
highlight default link orgHeading6 Function
highlight default link orgHeading7 Title
highlight default link orgHeading8 Identifier
highlight default link orgStars Title
highlight default link orgKeywordTodo Todo
highlight default link orgKeywordActive WarningMsg
highlight default link orgKeywordWait Type
highlight default link orgKeywordDone Comment
highlight default link orgPriority Special
highlight default link orgTags Comment
highlight default orgBold term=bold cterm=bold gui=bold
highlight default orgItalic term=italic cterm=italic gui=italic
highlight default orgUnderline term=underline cterm=underline gui=underline
highlight default orgStrike term=strikethrough cterm=strikethrough gui=strikethrough
highlight default link orgVerbatim String
highlight default link orgCode String
highlight default link orgMarker Comment
highlight default link orgLink Underlined
highlight default link orgLinkPlain Underlined
highlight default link orgBareUrl Underlined
highlight default link orgTimestamp Constant
highlight default link orgPlanning Constant
highlight default link orgPlanningLabel Comment
highlight default link orgComment Comment
highlight default link orgKeywordLine Comment
highlight default link orgDrawer Comment
highlight default link orgTable Identifier
highlight default link orgList Special
highlight default link orgBlock String
highlight default link orgBlockDelimiter Comment

b:current_syntax = 'org'
