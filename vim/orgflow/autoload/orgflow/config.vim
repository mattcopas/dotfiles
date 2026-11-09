vim9script
# Settings, in increasing priority:
#   1. defaults.json, generated from the VS Code extension's defaults
#   2. orgflow.* keys in vscode/settings.json, so both editors share one configuration
#   3. g:orgflow in your .vimrc, for anything that should differ in Vim
# As in VS Code, a list setting replaces the whole default rather than merging with it.
import './parser.vim'

const ROOT = fnamemodify(resolve(expand('<sfile>:p')), ':h:h:h')

var defaults: dict<any> = {}
var settings: dict<any> = {}
var settingsPath = ''
var settingsTime = -2
var orgConfig: dict<any> = {}
var orgConfigKey = ''

# Removes comments and trailing commas, which VS Code allows and json_decode doesn't.
export def StripJsonc(text: string): string
  var out: list<string> = []
  var chars = split(text, '\zs')
  var i = 0
  var count = len(chars)
  var inString = false
  while i < count
    var c = chars[i]
    if inString
      add(out, c)
      if c ==# '\' && i + 1 < count
        add(out, chars[i + 1])
        i += 1
      elseif c ==# '"'
        inString = false
      endif
    elseif c ==# '"'
      inString = true
      add(out, c)
    elseif c ==# '/' && i + 1 < count && chars[i + 1] ==# '/'
      while i < count && chars[i] !=# "\n"
        i += 1
      endwhile
      continue
    elseif c ==# '/' && i + 1 < count && chars[i + 1] ==# '*'
      i += 2
      while i + 1 < count && !(chars[i] ==# '*' && chars[i + 1] ==# '/')
        i += 1
      endwhile
      i += 1
    elseif c ==# ','
      var next = i + 1
      while next < count && chars[next] =~# '\s'
        next += 1
      endwhile
      # A comment between the comma and the closing bracket is rare enough to leave.
      if next >= count || (chars[next] !=# '}' && chars[next] !=# ']')
        add(out, c)
      endif
    else
      add(out, c)
    endif
    i += 1
  endwhile
  return join(out, '')
enddef

def SettingsFile(): string
  if exists('g:orgflow_settings_file')
    return expand(g:orgflow_settings_file)
  endif
  return simplify(ROOT .. '/../../vscode/settings.json')
enddef

def LoadSettings()
  var path = SettingsFile()
  var time = getftime(path)
  if path ==# settingsPath && time == settingsTime
    return
  endif
  settingsPath = path
  settingsTime = time
  settings = {}
  if time < 0
    return
  endif
  try
    var parsed = json_decode(StripJsonc(join(readfile(path), "\n")))
    if type(parsed) == v:t_dict
      for [key, value] in items(parsed)
        if strpart(key, 0, 8) ==# 'orgflow.'
          settings[strpart(key, 8)] = value
        endif
      endfor
    endif
  catch
    echohl WarningMsg
    echomsg 'Orgflow: ignoring ' .. path .. ': ' .. v:exception
    echohl None
  endtry
enddef

export def Get(key: string, fallback: any = v:none): any
  if empty(defaults)
    defaults = json_decode(join(readfile(ROOT .. '/defaults.json'), "\n"))
  endif
  if exists('g:orgflow') && has_key(g:orgflow, key)
    return g:orgflow[key]
  endif
  LoadSettings()
  if has_key(settings, key)
    return settings[key]
  endif
  if has_key(defaults, key)
    return defaults[key]
  endif
  return fallback
enddef

export def Expand(path: string): string
  if path ==# '~'
    return $HOME
  endif
  return strpart(path, 0, 2) ==# '~/' ? $HOME .. strpart(path, 1) : path
enddef

export def OrgConfig(): dict<any>
  var sequences = Get('todoKeywords')
  var key = json_encode(sequences)
  if key !=# orgConfigKey
    orgConfig = parser.MakeConfig(sequences)
    orgConfigKey = key
  endif
  return orgConfig
enddef

export def JournalConfig(): dict<any>
  return {
    fileFormat: Get('journal.fileFormat'),
    dateFormat: Get('journal.dateFormat'),
    carryover: Get('journal.carryover'),
  }
enddef
