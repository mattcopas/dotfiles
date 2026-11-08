#!/usr/bin/env node
// Generates the theme and grammars, so colours come straight from the Doom One
// palette and each embedded language doesn't have to be written out by hand.
// Run with `npm run assets`. The outputs are committed.
const { writeFileSync } = require("node:fs");
const { join } = require("node:path");

const root = join(__dirname, "..");

// emacs/elpaca/sources/themes/themes/doom-one-theme.el
const c = {
  bg: "#282c34",
  fg: "#bbc2cf",
  bgAlt: "#21242b",
  fgAlt: "#5B6268",
  base0: "#1B2229",
  base1: "#1c1f24",
  base2: "#202328",
  base3: "#23272e",
  base4: "#3f444a",
  base5: "#5B6268",
  base6: "#73797e",
  base7: "#9ca0a4",
  base8: "#DFDFDF",
  red: "#ff6c6b",
  orange: "#da8548",
  green: "#98be65",
  teal: "#4db5bd",
  yellow: "#ECBE7B",
  blue: "#51afef",
  darkBlue: "#2257A0",
  magenta: "#c678dd",
  violet: "#a9a1e1",
  cyan: "#46D9FF",
  darkCyan: "#5699AF",
};

function blend(a, b, amount) {
  const channel = (hex, i) => parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16);
  const out = [0, 1, 2].map((i) =>
    Math.round(channel(a, i) * amount + channel(b, i) * (1 - amount))
      .toString(16)
      .padStart(2, "0"),
  );
  return `#${out.join("")}`;
}
const lighten = (color, amount) => blend("#ffffff", color, amount);
const darken = (color, amount) => blend("#000000", color, amount);

const modelineBg = darken(c.bgAlt, 0.1);
const region = lighten(c.bgAlt, 0.15);
const docComment = lighten(c.base5, 0.25);
const variable = lighten(c.magenta, 0.4);
const levels = [
  c.blue,
  c.magenta,
  c.violet,
  lighten(c.blue, 0.25),
  lighten(c.magenta, 0.25),
  lighten(c.blue, 0.5),
  lighten(c.magenta, 0.5),
  lighten(c.blue, 0.8),
];

const colors = {
  focusBorder: c.blue,
  foreground: c.fg,
  descriptionForeground: c.base7,
  errorForeground: c.red,
  "selection.background": c.darkBlue,
  "widget.shadow": "#00000066",
  "icon.foreground": c.fg,

  "editor.background": c.bg,
  "editor.foreground": c.fg,
  "editorCursor.foreground": c.blue,
  "editor.lineHighlightBackground": c.bgAlt,
  "editor.lineHighlightBorder": "#00000000",
  "editor.selectionBackground": region,
  "editor.inactiveSelectionBackground": c.base4,
  "editor.selectionHighlightBackground": `${c.base4}aa`,
  "editor.wordHighlightBackground": `${c.base4}aa`,
  "editor.findMatchBackground": `${c.yellow}66`,
  "editor.findMatchHighlightBackground": `${c.yellow}33`,
  "editorLineNumber.foreground": c.base4,
  "editorLineNumber.activeForeground": c.fg,
  "editorIndentGuide.background1": c.base3,
  "editorIndentGuide.activeBackground1": c.base4,
  "editorWhitespace.foreground": c.base4,
  "editorBracketMatch.background": `${c.blue}33`,
  "editorBracketMatch.border": "#00000000",
  "editorBracketHighlight.foreground1": c.blue,
  "editorBracketHighlight.foreground2": c.magenta,
  "editorBracketHighlight.foreground3": c.green,
  "editorBracketHighlight.foreground4": c.orange,
  "editorBracketHighlight.foreground5": c.violet,
  "editorBracketHighlight.foreground6": c.yellow,
  "editorError.foreground": c.red,
  "editorWarning.foreground": c.yellow,
  "editorInfo.foreground": c.blue,
  "editorGutter.background": c.bg,
  "editorGutter.modifiedBackground": c.orange,
  "editorGutter.addedBackground": c.green,
  "editorGutter.deletedBackground": c.red,
  "editorGutter.foldingControlForeground": c.base5,
  "editor.foldBackground": `${c.base3}aa`,
  "editorWidget.background": c.bgAlt,
  "editorWidget.border": c.base1,
  "editorHoverWidget.background": c.bgAlt,
  "editorHoverWidget.border": c.base4,
  "editorSuggestWidget.background": c.bgAlt,
  "editorSuggestWidget.border": c.base1,
  "editorSuggestWidget.selectedBackground": c.base4,
  "editorGroup.border": c.base1,
  "editorGroupHeader.tabsBackground": c.bgAlt,
  "editorGroupHeader.noTabsBackground": c.bg,

  "tab.activeBackground": c.bg,
  "tab.inactiveBackground": c.bgAlt,
  "tab.activeForeground": c.fg,
  "tab.inactiveForeground": c.base6,
  "tab.border": c.base1,

  "sideBar.background": c.bgAlt,
  "sideBar.foreground": c.fg,
  "sideBar.border": c.base1,
  "sideBarTitle.foreground": c.base7,
  "sideBarSectionHeader.background": c.bgAlt,
  "activityBar.background": c.bgAlt,
  "activityBar.foreground": c.blue,
  "activityBar.inactiveForeground": c.base5,
  "activityBarBadge.background": c.blue,
  "activityBarBadge.foreground": c.base0,

  "list.activeSelectionBackground": c.base4,
  "list.activeSelectionForeground": c.base8,
  "list.inactiveSelectionBackground": c.base3,
  "list.hoverBackground": c.base3,
  "list.highlightForeground": c.blue,
  "list.focusBackground": c.base4,

  "input.background": c.base2,
  "input.foreground": c.fg,
  "input.border": c.base1,
  "input.placeholderForeground": c.base5,
  "dropdown.background": c.bgAlt,
  "button.background": c.blue,
  "button.foreground": c.base0,
  "badge.background": c.blue,
  "badge.foreground": c.base0,

  "quickInput.background": c.bgAlt,
  "quickInput.foreground": c.fg,
  "quickInputList.focusBackground": c.base4,
  "quickInputList.focusForeground": c.base8,
  "pickerGroup.foreground": c.blue,
  "pickerGroup.border": c.base4,

  "statusBar.background": modelineBg,
  "statusBar.foreground": c.fg,
  "statusBar.border": c.base1,
  "statusBar.noFolderBackground": modelineBg,
  "statusBar.debuggingBackground": c.orange,
  "statusBar.debuggingForeground": c.base0,
  "statusBarItem.hoverBackground": c.base4,
  "statusBarItem.remoteBackground": c.darkBlue,

  "titleBar.activeBackground": c.bgAlt,
  "titleBar.activeForeground": c.fg,
  "titleBar.inactiveBackground": c.bgAlt,
  "titleBar.inactiveForeground": c.base5,
  "titleBar.border": c.base1,
  "commandCenter.background": c.bg,
  "commandCenter.border": c.base4,

  "panel.background": c.bg,
  "panel.border": c.base1,
  "panelTitle.activeBorder": c.blue,
  "panelTitle.activeForeground": c.fg,
  "panelTitle.inactiveForeground": c.base5,

  "terminal.background": c.bg,
  "terminal.foreground": c.fg,
  "terminal.ansiBlack": c.base0,
  "terminal.ansiRed": c.red,
  "terminal.ansiGreen": c.green,
  "terminal.ansiYellow": c.yellow,
  "terminal.ansiBlue": c.blue,
  "terminal.ansiMagenta": c.magenta,
  "terminal.ansiCyan": c.cyan,
  "terminal.ansiWhite": c.fg,
  "terminal.ansiBrightBlack": c.base5,
  "terminal.ansiBrightRed": c.red,
  "terminal.ansiBrightGreen": c.green,
  "terminal.ansiBrightYellow": c.yellow,
  "terminal.ansiBrightBlue": c.blue,
  "terminal.ansiBrightMagenta": c.magenta,
  "terminal.ansiBrightCyan": c.cyan,
  "terminal.ansiBrightWhite": c.base8,

  "gitDecoration.modifiedResourceForeground": c.orange,
  "gitDecoration.addedResourceForeground": c.green,
  "gitDecoration.deletedResourceForeground": c.red,
  "gitDecoration.untrackedResourceForeground": c.green,
  "gitDecoration.ignoredResourceForeground": c.base5,
  "diffEditor.insertedTextBackground": `${c.green}22`,
  "diffEditor.removedTextBackground": `${c.red}22`,
  "scrollbarSlider.background": `${c.base4}66`,
  "scrollbarSlider.hoverBackground": `${c.base5}88`,
  "scrollbarSlider.activeBackground": `${c.blue}88`,
};

const token = (scope, foreground, fontStyle) => ({
  scope,
  settings: {
    ...(foreground ? { foreground } : {}),
    ...(fontStyle !== undefined ? { fontStyle } : {}),
  },
});

const tokenColors = [
  token(["comment", "punctuation.definition.comment"], c.base5),
  token(["comment.block.documentation", "string.quoted.docstring"], docComment),
  token(["string", "string.quoted"], c.green),
  token(["string.regexp", "constant.character.escape"], c.teal),
  token(["constant", "constant.language", "support.constant"], c.violet),
  token(["constant.numeric"], c.orange),
  token(["keyword", "keyword.control", "storage", "storage.type", "storage.modifier"], c.blue),
  token(["keyword.operator", "punctuation.accessor"], c.blue),
  token(["entity.name.function", "support.function", "meta.function-call"], c.magenta),
  token(["entity.name.function.member", "support.function.method"], c.cyan),
  token(["entity.name.type", "entity.name.class", "support.type", "support.class"], c.yellow),
  token(["entity.other.inherited-class"], c.yellow),
  token(["variable", "variable.other", "variable.parameter"], variable),
  token(["variable.language", "support.variable"], c.magenta),
  token(["entity.name.tag"], c.blue),
  token(["entity.other.attribute-name"], c.yellow),
  token(["punctuation", "meta.brace"], c.fg),
  token(["invalid"], c.red),
  token(["markup.bold"], undefined, "bold"),
  token(["markup.italic"], undefined, "italic"),
  token(["markup.underline"], undefined, "underline"),
  token(["markup.strikethrough"], undefined, "strikethrough"),
  token(["markup.inline.raw", "markup.fenced_code"], c.orange),
  token(["markup.quote"], c.base7, "italic"),
  token(["markup.list"], c.red),
  token(["markup.underline.link", "string.other.link"], c.blue, "underline"),
  token(["markup.inserted"], c.green),
  token(["markup.deleted"], c.red),
  token(["markup.changed"], c.orange),
  ...levels.map((color, i) =>
    token([`markup.heading.${i + 1}`, `markup.heading.${i + 1}.org`], color, "bold"),
  ),
  token(["markup.heading"], c.blue, "bold"),
  token(["entity.name.tag.org", "entity.name.tag.agenda"], docComment, ""),
  token(["constant.other.timestamp.org", "constant.other.planning.org"], c.yellow, ""),
  token(["keyword.other.planning.org"], c.base6),
  token(["keyword.other.drawer.org", "meta.keyword-line.org", "comment.org"], c.base5, ""),
  token(["meta.block.delimiter.org"], c.base5),
  token(["markup.other.table.org"], c.blue),
  token(["keyword.todo.agenda"], c.green, "bold"),
  token(["keyword.done.agenda"], c.base5, "bold"),
  token(["entity.name.section.agenda"], c.blue, "bold"),
  token(["string.date.agenda"], c.blue, "bold"),
  token(["constant.other.time.agenda"], c.yellow),
  token(["constant.other.leader.agenda"], c.orange),
  token(["comment.grid.agenda"], c.base5),
  token(["entity.name.function.now.agenda"], c.red),
  token(["entity.name.type.category.agenda"], c.teal),
  token(["constant.other.priority.agenda"], c.red),
  token(["comment.separator.agenda"], c.base4),
];

writeFileSync(
  join(root, "themes", "doom-one-color-theme.json"),
  `${JSON.stringify(
    {
      $schema: "vscode://schemas/color-theme",
      name: "Doom One",
      type: "dark",
      semanticHighlighting: true,
      colors,
      tokenColors,
    },
    null,
    2,
  )}\n`,
);

// Org grammar.
const embedded = [
  ["bash", "source.shell", "sh|bash|shell|zsh"],
  ["python", "source.python", "python|py"],
  ["javascript", "source.js", "js|javascript|jsx"],
  ["typescript", "source.ts", "ts|typescript|tsx"],
  ["json", "source.json", "json"],
  ["yaml", "source.yaml", "ya?ml"],
  ["java", "source.java", "java"],
  ["php", "source.php", "php"],
  ["sql", "source.sql", "sql"],
  ["go", "source.go", "go"],
  ["rust", "source.rust", "rust"],
  ["c", "source.c", "c"],
  ["cpp", "source.cpp", "c\\+\\+|cpp"],
  ["css", "source.css", "css"],
  ["html", "text.html.basic", "html"],
  ["xml", "text.xml", "xml"],
  ["markdown", "text.html.markdown", "markdown|md"],
  ["ruby", "source.ruby", "ruby"],
  ["dockerfile", "source.dockerfile", "dockerfile"],
];

const blockEnd = "^\\s*(?i:#\\+end_src)\\s*$";
const delimiter = { 0: { name: "meta.block.delimiter.org" } };

const grammar = {
  $schema:
    "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  name: "Org",
  scopeName: "source.org",
  patterns: [
    { include: "#headings" },
    { include: "#blocks" },
    { include: "#keywordLines" },
    { include: "#drawer" },
    { include: "#planning" },
    { include: "#comment" },
    { include: "#table" },
    { include: "#inline" },
  ],
  repository: {
    headings: {
      patterns: levels.map((_, i) => ({
        match: i < 7 ? `^(\\*{${i + 1}})( )(.*)$` : "^(\\*{8,})( )(.*)$",
        name: `markup.heading.${i + 1}.org`,
        captures: { 3: { patterns: [{ include: "#headingInner" }] } },
      })),
    },
    headingInner: {
      patterns: [
        {
          match: "(?:^|[ \\t]+)(:[\\w@#%:]+:)[ \\t]*$",
          captures: { 1: { name: "entity.name.tag.org" } },
        },
        { include: "#inline" },
      ],
    },
    blocks: {
      patterns: [
        ...embedded.map(([id, scope, names]) => ({
          begin: `^\\s*(?i:#\\+begin_src)\\s+(?:${names})\\b.*$`,
          end: blockEnd,
          beginCaptures: delimiter,
          endCaptures: delimiter,
          contentName: `meta.embedded.block.${id}`,
          patterns: [{ include: scope }],
        })),
        {
          begin: "^\\s*(?i:#\\+begin_src)\\b.*$",
          end: blockEnd,
          beginCaptures: delimiter,
          endCaptures: delimiter,
          contentName: "markup.fenced_code.block.org",
        },
        {
          begin: "^\\s*(?i:#\\+begin_quote)\\b.*$",
          end: "^\\s*(?i:#\\+end_quote)\\s*$",
          beginCaptures: delimiter,
          endCaptures: delimiter,
          contentName: "markup.quote.org",
        },
        {
          begin: "^\\s*(?i:#\\+begin_(example|export))\\b.*$",
          end: "^\\s*(?i:#\\+end_(example|export))\\s*$",
          beginCaptures: delimiter,
          endCaptures: delimiter,
          contentName: "markup.fenced_code.block.org",
        },
        {
          begin: "^\\s*(?i:#\\+begin_\\w+)\\b.*$",
          end: "^\\s*(?i:#\\+end_\\w+)\\s*$",
          beginCaptures: delimiter,
          endCaptures: delimiter,
        },
      ],
    },
    keywordLines: { match: "^\\s*#\\+\\w+:.*$", name: "meta.keyword-line.org" },
    drawer: { match: "^\\s*:[\\w-]+:(\\s+.*)?$", name: "keyword.other.drawer.org" },
    planning: {
      match: "^\\s*(?:(?:SCHEDULED|DEADLINE|CLOSED):\\s*(?:<[^>]*>|\\[[^\\]]*\\])\\s*)+$",
      captures: { 0: { patterns: [{ include: "#planningInner" }] } },
    },
    planningInner: {
      patterns: [
        { match: "SCHEDULED:|DEADLINE:|CLOSED:", name: "keyword.other.planning.org" },
        { include: "#timestamp" },
      ],
    },
    comment: { match: "^\\s*#(\\s.*)?$", name: "comment.org" },
    table: { match: "^\\s*\\|.*$", name: "markup.other.table.org" },
    inline: {
      patterns: [
        { include: "#timestamp" },
        { match: "\\[\\[[^\\]\\n]+\\](?:\\[[^\\]\\n]*\\])?\\]", name: "string.other.link.org" },
        { match: "\\bhttps?://[^\\s\\]>)]+", name: "string.other.link.org" },
        { match: "^\\s*(?:[-+]|\\d+[.)])\\s", name: "markup.list.org" },
      ],
    },
    timestamp: {
      match: "[<\\[]\\d{4}-\\d{2}-\\d{2}[^>\\]\\n]*[>\\]]",
      name: "constant.other.timestamp.org",
    },
  },
};
writeFileSync(
  join(root, "syntaxes", "org.tmLanguage.json"),
  `${JSON.stringify(grammar, null, 2)}\n`,
);

// Agenda grammar.
const agendaKeywords = {
  todo: "TODO|IN PROGRESS|IN REVIEW|LOOP|STRT|WAIT|HOLD|IDEA|\\[ \\]|\\[-\\]|\\[\\?\\]",
  done: "DONE|KILL|\\[X\\]|OKAY|YES|NO",
};
const agendaGrammar = {
  $schema:
    "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  name: "Org Agenda",
  scopeName: "source.org-agenda",
  patterns: [
    { match: "^=+$", name: "comment.separator.agenda" },
    {
      match: "^(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\\b.*$",
      name: "string.date.agenda",
    },
    {
      match: "^\\s+[ \\d]\\d:\\d\\d\\.{6} -+$",
      name: "comment.grid.agenda",
    },
    {
      match: "^\\s+[ \\d]\\d:\\d\\d\\.{6} now[ -]*$",
      name: "entity.name.function.now.agenda",
    },
    { begin: "^  (?=\\S+:\\s)", end: "$", patterns: [{ include: "#item" }] },
    { match: "^\\S.*$", name: "entity.name.section.agenda" },
  ],
  repository: {
    item: {
      patterns: [
        { match: "\\G\\S+:", name: "entity.name.type.category.agenda" },
        { match: "[ \\d]\\d:\\d\\d(?:\\.{6}|-\\d+:\\d\\d)", name: "constant.other.time.agenda" },
        {
          match: "(?:Scheduled:|Deadline:|Sched\\.\\s*\\d+x:|In\\s+\\d+ d\\.:|\\s*\\d+ d\\. ago:)",
          name: "constant.other.leader.agenda",
        },
        { match: `(?<=\\s)(?:${agendaKeywords.done})(?=\\s|$)`, name: "keyword.done.agenda" },
        { match: `(?<=\\s)(?:${agendaKeywords.todo})(?=\\s|$)`, name: "keyword.todo.agenda" },
        { match: "\\[#[A-Z0-9]+\\]", name: "constant.other.priority.agenda" },
        { match: "\\s(:[\\w@#%:]+:)$", captures: { 1: { name: "entity.name.tag.agenda" } } },
      ],
    },
  },
};
writeFileSync(
  join(root, "syntaxes", "org-agenda.tmLanguage.json"),
  `${JSON.stringify(agendaGrammar, null, 2)}\n`,
);
