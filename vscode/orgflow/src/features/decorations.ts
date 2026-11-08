// The org-modern and org-appear look: bullets for stars, hidden emphasis markers
// and link targets, and everything revealed again on the cursor line. Colours are
// from Doom One, including doom-themes' org faces.
import * as vscode from "vscode";
import { OrgConfig, parseHeadingLine } from "../org/parser";
import { findLinks } from "./language";
import { hideMarkup, orgConfig } from "./settings";

const HIDDEN = "none; font-size: 0; letter-spacing: -1px";
const BULLETS = ["◉", "○", "✸", "✿", "✤", "✜"];
const LEVEL_COLORS = ["#51afef", "#c678dd", "#a9a1e1", "#7cc3f3", "#d49ae5", "#a8d7f7", "#e2bbee", "#dceffb"];
const LIST_BULLETS: Record<string, string> = { "-": "•", "+": "➤" };

const decoration = vscode.window.createTextEditorDecorationType;

const types = {
  hidden: decoration({ textDecoration: HIDDEN }),
  bullets: LEVEL_COLORS.map((color, level) =>
    decoration({
      textDecoration: HIDDEN,
      before: {
        contentText: `${" ".repeat(level * 2)}${BULLETS[level % BULLETS.length]}`,
        color,
        fontWeight: "bold",
      },
    }),
  ),
  listBullets: Object.fromEntries(
    Object.entries(LIST_BULLETS).map(([marker, bullet]) => [
      marker,
      decoration({
        textDecoration: HIDDEN,
        before: { contentText: bullet, color: "#ff6c6b" },
      }),
    ]),
  ) as Record<string, vscode.TextEditorDecorationType>,
  todo: decoration({ color: "#98be65", fontWeight: "bold" }),
  done: decoration({ color: "#5B6268", fontWeight: "bold" }),
  doneHeading: decoration({ color: "#5B6268" }),
  priorityA: decoration({ color: "#ff6c6b", fontWeight: "bold" }),
  priorityB: decoration({ color: "#ECBE7B", fontWeight: "bold" }),
  priorityC: decoration({ color: "#98be65", fontWeight: "bold" }),
  bold: decoration({ fontWeight: "bold" }),
  italic: decoration({ fontStyle: "italic" }),
  underline: decoration({ textDecoration: "underline" }),
  strike: decoration({ textDecoration: "line-through" }),
  code: decoration({ color: "#da8548", backgroundColor: "#23272e" }),
  verbatim: decoration({ color: "#98be65", backgroundColor: "#23272e" }),
  link: decoration({ color: "#51afef", textDecoration: "underline" }),
  block: decoration({ isWholeLine: true, backgroundColor: "#23272e" }),
};

const EMPHASIS =
  /(^|[\s\-('"{])([*/_=~+])(?=\S)(.*?\S)\2(?=$|[\s\-.,:;!?'")}\]])/g;

type Ranges = Map<vscode.TextEditorDecorationType, vscode.Range[]>;

function add(ranges: Ranges, type: vscode.TextEditorDecorationType, range: vscode.Range) {
  const list = ranges.get(type);
  if (list) {
    list.push(range);
  } else {
    ranges.set(type, [range]);
  }
}

function decorateHeading(
  ranges: Ranges,
  line: string,
  at: number,
  config: OrgConfig,
  reveal: boolean,
  hide: boolean,
) {
  const parsed = parseHeadingLine(line, config);
  if (!parsed) {
    return;
  }
  if (hide && !reveal) {
    const type = types.bullets[(parsed.level - 1) % types.bullets.length];
    add(ranges, type, new vscode.Range(at, 0, at, parsed.level));
  }
  let column = parsed.level + 1;
  if (parsed.keyword) {
    const done = config.doneWords.has(parsed.keyword);
    add(
      ranges,
      done ? types.done : types.todo,
      new vscode.Range(at, column, at, column + parsed.keyword.length),
    );
    if (done) {
      add(
        ranges,
        types.doneHeading,
        new vscode.Range(at, column + parsed.keyword.length, at, parsed.level + 1 + parsed.text.length),
      );
    }
    column += parsed.keyword.length + 1;
  }
  if (parsed.priority) {
    const start = line.indexOf(`[#${parsed.priority}]`, column);
    if (start >= 0) {
      const type =
        parsed.priority === "A"
          ? types.priorityA
          : parsed.priority === "B"
            ? types.priorityB
            : types.priorityC;
      add(ranges, type, new vscode.Range(at, start, at, start + parsed.priority.length + 3));
    }
  }
}

function decorateInline(
  ranges: Ranges,
  line: string,
  at: number,
  reveal: boolean,
  hide: boolean,
) {
  const links = findLinks(line);
  let masked = line;
  for (const link of links) {
    masked =
      masked.slice(0, link.start) +
      " ".repeat(link.end - link.start) +
      masked.slice(link.end);
    if (link.descriptionStart !== null && link.description !== null) {
      const start = link.descriptionStart;
      const end = start + link.description.length;
      add(ranges, types.link, new vscode.Range(at, start, at, end));
      if (hide && !reveal) {
        add(ranges, types.hidden, new vscode.Range(at, link.start, at, start));
        add(ranges, types.hidden, new vscode.Range(at, end, at, link.end));
      }
    } else if (link.start !== link.targetStart) {
      const end = link.targetStart + link.target.length;
      add(ranges, types.link, new vscode.Range(at, link.targetStart, at, end));
      if (hide && !reveal) {
        add(ranges, types.hidden, new vscode.Range(at, link.start, at, link.targetStart));
        add(ranges, types.hidden, new vscode.Range(at, end, at, link.end));
      }
    } else {
      add(ranges, types.link, new vscode.Range(at, link.start, at, link.end));
    }
  }

  EMPHASIS.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = EMPHASIS.exec(masked))) {
    const open = match.index + match[1].length;
    const close = open + 1 + match[3].length;
    const type = {
      "*": types.bold,
      "/": types.italic,
      _: types.underline,
      "+": types.strike,
      "=": types.verbatim,
      "~": types.code,
    }[match[2]];
    if (type) {
      add(ranges, type, new vscode.Range(at, open + 1, at, close));
    }
    if (hide && !reveal) {
      add(ranges, types.hidden, new vscode.Range(at, open, at, open + 1));
      add(ranges, types.hidden, new vscode.Range(at, close, at, close + 1));
    }
    // A closing marker can also open the next run, so step back onto it.
    EMPHASIS.lastIndex = close + 1;
  }
}

function allTypes(): vscode.TextEditorDecorationType[] {
  return [
    types.hidden,
    ...types.bullets,
    ...Object.values(types.listBullets),
    types.todo,
    types.done,
    types.doneHeading,
    types.priorityA,
    types.priorityB,
    types.priorityC,
    types.bold,
    types.italic,
    types.underline,
    types.strike,
    types.code,
    types.verbatim,
    types.link,
    types.block,
  ];
}

export function computeDecorations(
  lines: string[],
  cursorLines: Set<number>,
  config: OrgConfig,
  hide: boolean,
): Ranges {
  const ranges: Ranges = new Map();
  let inBlock = false;
  lines.forEach((line, at) => {
    const reveal = cursorLines.has(at);
    if (/^\s*#\+begin_/i.test(line)) {
      inBlock = true;
      add(ranges, types.block, new vscode.Range(at, 0, at, 0));
      return;
    }
    if (/^\s*#\+end_/i.test(line)) {
      inBlock = false;
      add(ranges, types.block, new vscode.Range(at, 0, at, 0));
      return;
    }
    if (inBlock) {
      add(ranges, types.block, new vscode.Range(at, 0, at, 0));
      return;
    }
    if (/^\*+ /.test(line)) {
      decorateHeading(ranges, line, at, config, reveal, hide);
      decorateInline(ranges, line.replace(/^\*+/, (s) => " ".repeat(s.length)), at, reveal, hide);
      return;
    }
    if (/^\s*[|#:]/.test(line) || /^\s*(SCHEDULED|DEADLINE|CLOSED):/.test(line)) {
      if (!/^\s*\|/.test(line)) {
        return;
      }
    }
    const list = line.match(/^(\s*)([-+]) /);
    if (list && hide && !reveal) {
      const start = list[1].length;
      add(ranges, types.listBullets[list[2]], new vscode.Range(at, start, at, start + 1));
    }
    decorateInline(ranges, line, at, reveal, hide);
  });
  return ranges;
}

function update(editor: vscode.TextEditor) {
  if (editor.document.languageId !== "org") {
    return;
  }
  const lines = editor.document.getText().split(/\r?\n/);
  const cursors = new Set(editor.selections.map((s) => s.active.line));
  const ranges = computeDecorations(lines, cursors, orgConfig(), hideMarkup());
  for (const type of allTypes()) {
    editor.setDecorations(type, ranges.get(type) ?? []);
  }
}

export function activateDecorations(context: vscode.ExtensionContext) {
  let timer: NodeJS.Timeout | undefined;
  const refreshVisible = () => {
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(() => vscode.window.visibleTextEditors.forEach(update), 60);
  };
  context.subscriptions.push(
    ...allTypes(),
    vscode.window.onDidChangeVisibleTextEditors(refreshVisible),
    vscode.window.onDidChangeTextEditorSelection((event) => {
      if (event.textEditor.document.languageId === "org") {
        update(event.textEditor);
      }
    }),
    vscode.workspace.onDidChangeTextDocument((event) => {
      if (event.document.languageId === "org") {
        refreshVisible();
      }
    }),
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (event.affectsConfiguration("orgflow")) {
        refreshVisible();
      }
    }),
  );
  refreshVisible();
}
