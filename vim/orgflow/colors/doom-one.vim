vim9script
# Doom One for Vim. Colours come from emacs/elpaca/sources/themes/themes/doom-one-theme.el,
# which is MIT licensed (see NOTICE). In a terminal without true colour, each colour falls
# back to its nearest match in the 256-colour palette, which is close but not exact.

highlight clear
if exists('syntax_on')
  syntax reset
endif
set background=dark
g:colors_name = 'doom-one'

const C: dict<string> = {
  bg: '#282c34', fg: '#bbc2cf', bgAlt: '#21242b', fgAlt: '#5B6268',
  base0: '#1B2229', base1: '#1c1f24', base2: '#202328', base3: '#23272e',
  base4: '#3f444a', base5: '#5B6268', base6: '#73797e', base7: '#9ca0a4', base8: '#DFDFDF',
  red: '#ff6c6b', orange: '#da8548', green: '#98be65', teal: '#4db5bd', yellow: '#ECBE7B',
  blue: '#51afef', darkBlue: '#2257A0', magenta: '#c678dd', violet: '#a9a1e1',
  cyan: '#46D9FF', darkCyan: '#5699AF',
  # doom-themes' outline faces lighten blue and magenta for the deeper levels.
  blue25: '#7cc3f3', magenta25: '#d499e5', blue50: '#a8d7f7', magenta50: '#e2bbee',
  comment: '#5B6268', docComment: '#83898d',
}

def Channel(hex: string, at: number): number
  return str2nr(strpart(hex, 1 + at * 2, 2), 16)
enddef

# The nearest colour in xterm's 6x6x6 cube or grey ramp.
def Nearest(hex: string): number
  var rgb = [Channel(hex, 0), Channel(hex, 1), Channel(hex, 2)]
  const LEVELS = [0, 95, 135, 175, 215, 255]
  var cube: list<number> = []
  for value in rgb
    var best = 0
    var at = 0
    for level in LEVELS
      if abs(level - value) < abs(LEVELS[best] - value)
        best = at
      endif
      at += 1
    endfor
    add(cube, best)
  endfor
  var cubeError = 0
  var at = 0
  for value in rgb
    cubeError += (LEVELS[cube[at]] - value) * (LEVELS[cube[at]] - value)
    at += 1
  endfor
  var grey = (rgb[0] + rgb[1] + rgb[2]) / 3
  var step = min([23, max([0, (grey - 8 + 5) / 10])])
  var greyLevel = 8 + step * 10
  var greyError = 0
  for value in rgb
    greyError += (greyLevel - value) * (greyLevel - value)
  endfor
  return greyError < cubeError ? 232 + step : 16 + 36 * cube[0] + 6 * cube[1] + cube[2]
enddef

def Hi(group: string, fg: string, bg: string = '', style: string = '')
  var parts = ['highlight', group]
  if fg !=# ''
    add(parts, 'guifg=' .. C[fg])
    add(parts, 'ctermfg=' .. Nearest(C[fg]))
  else
    extend(parts, ['guifg=NONE', 'ctermfg=NONE'])
  endif
  if bg !=# ''
    add(parts, 'guibg=' .. C[bg])
    add(parts, 'ctermbg=' .. Nearest(C[bg]))
  else
    extend(parts, ['guibg=NONE', 'ctermbg=NONE'])
  endif
  var attr = style !=# '' ? style : 'NONE'
  extend(parts, ['gui=' .. attr, 'cterm=' .. attr, 'term=' .. attr])
  execute join(parts, ' ')
enddef

# Editor
Hi('Normal', 'fg', 'bg')
Hi('NonText', 'base5')
Hi('EndOfBuffer', 'bg')
Hi('LineNr', 'base5')
Hi('CursorLineNr', 'fg', '', 'bold')
Hi('CursorLine', '', 'bgAlt')
Hi('CursorColumn', '', 'bgAlt')
Hi('ColorColumn', '', 'bgAlt')
Hi('SignColumn', 'base5', 'bg')
Hi('VertSplit', 'base1', 'base1')
Hi('Visual', '', 'base4')
Hi('VisualNOS', '', 'base4')
Hi('Search', 'bg', 'yellow')
Hi('IncSearch', 'bg', 'orange', 'bold')
Hi('CurSearch', 'bg', 'orange', 'bold')
Hi('MatchParen', 'red', 'base4', 'bold')
Hi('Folded', 'base7', 'bgAlt')
Hi('FoldColumn', 'base5', 'bg')
Hi('StatusLine', 'fg', 'base2')
Hi('StatusLineNC', 'base5', 'base1')
Hi('StatusLineTerm', 'fg', 'base2')
Hi('StatusLineTermNC', 'base5', 'base1')
Hi('TabLine', 'base5', 'bgAlt')
Hi('TabLineFill', 'base5', 'bgAlt')
Hi('TabLineSel', 'fg', 'bg', 'bold')
Hi('WildMenu', 'bg', 'blue')
Hi('Pmenu', 'fg', 'bgAlt')
Hi('PmenuSel', 'base0', 'blue')
Hi('PmenuSbar', '', 'base2')
Hi('PmenuThumb', '', 'base5')
Hi('ErrorMsg', 'red', '', 'bold')
Hi('WarningMsg', 'yellow')
Hi('ModeMsg', 'fg', '', 'bold')
Hi('MoreMsg', 'green')
Hi('Question', 'green')
Hi('Directory', 'blue')
Hi('SpecialKey', 'base5')
Hi('Conceal', 'base5')
Hi('QuickFixLine', '', 'base4')
Hi('SpellBad', 'red', '', 'underline')
Hi('SpellCap', 'yellow', '', 'underline')
Hi('SpellRare', 'violet', '', 'underline')
Hi('SpellLocal', 'teal', '', 'underline')
Hi('DiffAdd', 'green', 'base3')
Hi('DiffChange', 'yellow', 'base3')
Hi('DiffDelete', 'red', 'base3')
Hi('DiffText', 'orange', 'base4', 'bold')

# Syntax
Hi('Comment', 'comment')
Hi('Constant', 'violet')
Hi('String', 'green')
Hi('Character', 'green')
Hi('Number', 'orange')
Hi('Boolean', 'orange')
Hi('Float', 'orange')
Hi('Identifier', 'magenta')
Hi('Function', 'magenta')
Hi('Statement', 'blue')
Hi('Conditional', 'blue')
Hi('Repeat', 'blue')
Hi('Label', 'blue')
Hi('Operator', 'blue')
Hi('Keyword', 'blue')
Hi('Exception', 'blue')
Hi('PreProc', 'magenta')
Hi('Include', 'blue')
Hi('Define', 'blue')
Hi('Macro', 'blue')
Hi('PreCondit', 'blue')
Hi('Type', 'yellow')
Hi('StorageClass', 'blue')
Hi('Structure', 'yellow')
Hi('Typedef', 'yellow')
Hi('Special', 'teal')
Hi('SpecialChar', 'teal')
Hi('Tag', 'blue')
Hi('Delimiter', 'fg')
Hi('SpecialComment', 'docComment')
Hi('Debug', 'red')
Hi('Underlined', 'blue', '', 'underline')
Hi('Ignore', 'base5')
Hi('Error', 'red', '', 'bold')
Hi('Todo', 'green', '', 'bold')
Hi('Title', 'blue', '', 'bold')

# Org
Hi('orgHeading1', 'blue', '', 'bold')
Hi('orgHeading2', 'magenta', '', 'bold')
Hi('orgHeading3', 'violet', '', 'bold')
Hi('orgHeading4', 'blue25', '', 'bold')
Hi('orgHeading5', 'magenta25', '', 'bold')
Hi('orgHeading6', 'blue50', '', 'bold')
Hi('orgHeading7', 'magenta50', '', 'bold')
Hi('orgHeading8', 'blue25', '', 'bold')
Hi('orgStars', 'base6')
Hi('orgKeywordTodo', 'green', '', 'bold')
Hi('orgKeywordActive', 'yellow', '', 'bold')
Hi('orgKeywordWait', 'orange', '', 'bold')
Hi('orgKeywordDone', 'base5', '', 'bold')
Hi('orgPriority', 'orange')
Hi('orgTags', 'docComment')
Hi('orgBold', 'orange', '', 'bold')
Hi('orgItalic', 'fg', '', 'italic')
Hi('orgUnderline', 'fg', '', 'underline')
Hi('orgStrike', 'base6', '', 'strikethrough')
Hi('orgVerbatim', 'green')
Hi('orgCode', 'orange')
Hi('orgMarker', 'base5')
Hi('orgLink', 'blue', '', 'underline')
Hi('orgLinkPlain', 'blue', '', 'underline')
Hi('orgBareUrl', 'blue', '', 'underline')
Hi('orgTimestamp', 'yellow')
Hi('orgPlanning', 'yellow')
Hi('orgPlanningLabel', 'base6')
Hi('orgComment', 'comment')
Hi('orgKeywordLine', 'base5')
Hi('orgDrawer', 'base5')
Hi('orgTable', 'blue')
Hi('orgList', 'orange')
Hi('orgBlock', 'fg')
Hi('orgBlockDelimiter', 'base5')

# Agenda
Hi('orgAgendaHeader', 'magenta', '', 'bold')
Hi('orgAgendaDay', 'blue', '', 'bold')
Hi('orgAgendaSeparator', 'base5')
Hi('orgAgendaGrid', 'base5')
Hi('orgAgendaNow', 'yellow')
Hi('orgAgendaCategory', 'docComment')
Hi('orgAgendaDeadline', 'red')
Hi('orgAgendaOverdue', 'orange')
Hi('orgAgendaScheduled', 'green')
Hi('orgAgendaTime', 'yellow')
Hi('orgAgendaTags', 'docComment')
Hi('orgAgendaPriority', 'orange')
Hi('orgAgendaTodo', 'green', '', 'bold')
Hi('orgAgendaActive', 'yellow', '', 'bold')
Hi('orgAgendaWait', 'orange', '', 'bold')
Hi('orgAgendaDone', 'base5', '', 'bold')

# which-key and the picker
Hi('OrgflowMenu', 'fg', 'bgAlt')
Hi('OrgflowMenuKey', 'blue', '', 'bold')
Hi('OrgflowMenuGroup', 'magenta')
Hi('OrgflowMenuTitle', 'base7', '', 'bold')
Hi('OrgflowPicker', 'fg', 'bgAlt')
Hi('OrgflowPickerBorder', 'base5', 'bgAlt')
Hi('OrgflowPickerSelected', '', 'base4')
Hi('OrgflowPickerMatch', 'blue', '', 'bold')
Hi('OrgflowPickerPrompt', 'blue', '', 'bold')
