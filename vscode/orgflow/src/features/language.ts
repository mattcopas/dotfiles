// Folding, outline and links for org files, plus TAB and S-TAB fold cycling.
import { dirname, isAbsolute, join } from "node:path";
import * as vscode from "vscode";
import { OrgDocument, OrgHeading, parseOrg } from "../org/parser";
import { normalized, showFresh } from "./files";
import { expandPath, orgConfig, startupFolded } from "./settings";

export function parseDocument(document: vscode.TextDocument): OrgDocument {
  return parseOrg(normalized(document), orgConfig());
}

function lastContentLine(lines: string[], from: number, end: number): number {
  let last = end - 1;
  while (last > from && lines[last].trim() === "") {
    last--;
  }
  return last;
}

const folding: vscode.FoldingRangeProvider = {
  provideFoldingRanges(document) {
    const doc = parseDocument(document);
    const ranges: vscode.FoldingRange[] = [];
    for (const heading of doc.headings) {
      const end = lastContentLine(doc.lines, heading.line, heading.subtreeEnd);
      if (end > heading.line) {
        ranges.push(new vscode.FoldingRange(heading.line, end));
      }
    }
    let open: number | null = null;
    doc.lines.forEach((line, at) => {
      if (/^\s*#\+begin_/i.test(line) || /^\s*:(PROPERTIES|LOGBOOK):\s*$/.test(line)) {
        open = at;
      } else if (open !== null && (/^\s*#\+end_/i.test(line) || /^\s*:END:\s*$/.test(line))) {
        ranges.push(new vscode.FoldingRange(open, at, vscode.FoldingRangeKind.Region));
        open = null;
      }
    });
    return ranges;
  },
};

const symbols: vscode.DocumentSymbolProvider = {
  provideDocumentSymbols(document) {
    const doc = parseDocument(document);
    const roots: vscode.DocumentSymbol[] = [];
    const stack: { level: number; symbol: vscode.DocumentSymbol }[] = [];
    for (const heading of doc.headings) {
      const range = new vscode.Range(
        heading.line,
        0,
        Math.max(heading.line, heading.subtreeEnd - 1),
        doc.lines[Math.max(heading.line, heading.subtreeEnd - 1)].length,
      );
      const symbol = new vscode.DocumentSymbol(
        heading.title || "(no title)",
        heading.keyword ?? "",
        vscode.SymbolKind.Namespace,
        range,
        new vscode.Range(heading.line, 0, heading.line, doc.lines[heading.line].length),
      );
      while (stack.length && stack[stack.length - 1].level >= heading.level) {
        stack.pop();
      }
      if (stack.length) {
        stack[stack.length - 1].symbol.children.push(symbol);
      } else {
        roots.push(symbol);
      }
      stack.push({ level: heading.level, symbol });
    }
    return roots;
  },
};

export interface OrgLink {
  start: number;
  end: number;
  target: string;
  description: string | null;
  /** Column where the target starts, and the description, inside the line. */
  targetStart: number;
  descriptionStart: number | null;
}

const BRACKET_LINK = /\[\[([^\]\n]+)\](?:\[([^\]\n]*)\])?\]/g;
const BARE_URL = /\bhttps?:\/\/[^\s\]>)]+/g;

export function findLinks(line: string): OrgLink[] {
  const links: OrgLink[] = [];
  BRACKET_LINK.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = BRACKET_LINK.exec(line))) {
    links.push({
      start: match.index,
      end: match.index + match[0].length,
      target: match[1],
      description: match[2] ?? null,
      targetStart: match.index + 2,
      descriptionStart:
        match[2] !== undefined ? match.index + 2 + match[1].length + 2 : null,
    });
  }
  BARE_URL.lastIndex = 0;
  while ((match = BARE_URL.exec(line))) {
    const start = match.index;
    if (!links.some((link) => start >= link.start && start < link.end)) {
      links.push({
        start,
        end: start + match[0].length,
        target: match[0],
        description: null,
        targetStart: start,
        descriptionStart: null,
      });
    }
  }
  return links;
}

interface ResolvedLink {
  uri?: vscode.Uri;
  file?: string;
  search?: string;
}

function resolveLink(target: string, document: vscode.TextDocument): ResolvedLink {
  if (/^(https?|mailto):/.test(target)) {
    return { uri: vscode.Uri.parse(target) };
  }
  const internal = target.startsWith("*") || target.startsWith("#");
  if (internal) {
    return { file: document.uri.fsPath, search: target };
  }
  const path = target.replace(/^file(\+[a-z]+)?:/, "");
  const [rawFile, search] = path.split("::");
  const expanded = expandPath(rawFile);
  const file = isAbsolute(expanded)
    ? expanded
    : join(dirname(document.uri.fsPath), expanded);
  return { file, search };
}

const links: vscode.DocumentLinkProvider = {
  provideDocumentLinks(document) {
    const found: vscode.DocumentLink[] = [];
    for (let at = 0; at < document.lineCount; at++) {
      for (const link of findLinks(document.lineAt(at).text)) {
        const args = encodeURIComponent(JSON.stringify([document.uri.toString(), link.target]));
        found.push(
          new vscode.DocumentLink(
            new vscode.Range(at, link.start, at, link.end),
            vscode.Uri.parse(`command:orgflow.org.followLink?${args}`),
          ),
        );
      }
    }
    return found;
  },
};

function searchLine(document: vscode.TextDocument, search: string): number | null {
  const doc = parseDocument(document);
  if (search.startsWith("*")) {
    const title = search.replace(/^\*+\s*/, "");
    return doc.headings.find((h) => h.title === title)?.line ?? null;
  }
  if (search.startsWith("#")) {
    const id = search.slice(1);
    return doc.headings.find((h) => h.properties.get("CUSTOM_ID") === id)?.line ?? null;
  }
  if (/^\d+$/.test(search)) {
    return Number(search) - 1;
  }
  const at = doc.lines.findIndex((line) => line.includes(search));
  return at >= 0 ? at : null;
}

export async function revealLine(editor: vscode.TextEditor, line: number, column = 0) {
  const position = new vscode.Position(line, column);
  editor.selection = new vscode.Selection(position, position);
  await vscode.commands.executeCommand("editor.unfold", { selectionLines: [line], levels: 1, direction: "up" });
  editor.revealRange(new vscode.Range(position, position), vscode.TextEditorRevealType.InCenterIfOutsideViewport);
}

async function followLink(documentUri: string, target: string) {
  const document = await vscode.workspace.openTextDocument(vscode.Uri.parse(documentUri));
  const resolved = resolveLink(target, document);
  if (resolved.uri) {
    await vscode.env.openExternal(resolved.uri);
    return;
  }
  if (!resolved.file) {
    return;
  }
  markOpened(vscode.Uri.file(resolved.file));
  let editor: vscode.TextEditor;
  try {
    editor = await showFresh(resolved.file);
  } catch {
    vscode.window.showWarningMessage(`Can't open ${resolved.file}`);
    return;
  }
  if (resolved.search) {
    const line = searchLine(editor.document, resolved.search);
    if (line === null) {
      vscode.window.showWarningMessage(`Couldn't find ${resolved.search}`);
    } else {
      await revealLine(editor, line);
    }
  }
}

export function linkAtCursor(editor: vscode.TextEditor): OrgLink | undefined {
  const { line, character } = editor.selection.active;
  return findLinks(editor.document.lineAt(line).text).find(
    (link) => character >= link.start && character < link.end,
  );
}

// Fold cycling. VS Code has no API for reading fold state, and visibleRanges can go
// stale after a fold (seen with VSCodeVim active), so what was last asked for wins. The
// visible lines are only a fallback for a heading this code hasn't touched. Folding by
// other means, like za, can leave this one step behind until the next TAB.
type SubtreeState = "folded" | "children" | "subtree";
type GlobalState = "overview" | "contents" | "all";

const subtreeStates = new Map<string, { version: number; states: Map<number, SubtreeState> }>();
const globalStates = new Map<string, GlobalState>();
const opened = new Set<string>();

function statesFor(document: vscode.TextDocument) {
  const key = document.uri.toString();
  let entry = subtreeStates.get(key);
  if (!entry || entry.version !== document.version) {
    entry = { version: document.version, states: new Map() };
    subtreeStates.set(key, entry);
  }
  return entry.states;
}

function isHidden(editor: vscode.TextEditor, line: number): boolean {
  const ranges = editor.visibleRanges;
  const inside = ranges.some((r) => r.start.line <= line && line <= r.end.line);
  if (inside) {
    return false;
  }
  // A line past the bottom of the viewport isn't hidden, only out of view.
  const after = ranges.some((r) => r.start.line > line);
  return after;
}

const fold = (lines: number[]) =>
  lines.length
    ? vscode.commands.executeCommand("editor.fold", { selectionLines: lines, levels: 1, direction: "down" })
    : Promise.resolve();
const unfoldAllBelow = (line: number) =>
  vscode.commands.executeCommand("editor.unfold", { selectionLines: [line], levels: 100, direction: "down" });

function directChildren(doc: OrgDocument, heading: OrgHeading): OrgHeading[] {
  return doc.headings.filter((h) => h.parent === heading.index);
}

export async function cycleHeading(editor: vscode.TextEditor, heading: OrgHeading, doc: OrgDocument) {
  const states = statesFor(editor.document);
  const children = directChildren(doc, heading);
  const hasBody = lastContentLine(doc.lines, heading.line, heading.subtreeEnd) > heading.line;
  if (!hasBody) {
    vscode.window.setStatusBarMessage("EMPTY ENTRY", 1500);
    return;
  }
  const current: SubtreeState =
    states.get(heading.line) ?? (isHidden(editor, heading.line + 1) ? "folded" : "subtree");
  let next: SubtreeState;
  if (current === "folded") {
    next = children.length ? "children" : "subtree";
  } else if (current === "children") {
    next = "subtree";
  } else {
    next = "folded";
  }
  if (next === "folded") {
    await fold([heading.line]);
    vscode.window.setStatusBarMessage("FOLDED", 1500);
  } else if (next === "children") {
    await unfoldAllBelow(heading.line);
    await fold(children.map((child) => child.line));
    vscode.window.setStatusBarMessage("CHILDREN", 1500);
  } else {
    await unfoldAllBelow(heading.line);
    vscode.window.setStatusBarMessage("SUBTREE", 1500);
  }
  statesFor(editor.document).set(heading.line, next);
}

async function applyOverview(editor: vscode.TextEditor) {
  const doc = parseDocument(editor.document);
  const states = statesFor(editor.document);
  states.clear();
  await vscode.commands.executeCommand("editor.unfoldAll");
  const top = doc.headings.filter((h) => h.level === 1).map((h) => h.line);
  await fold(top);
  top.forEach((line) => states.set(line, "folded"));
}

export async function cycleGlobal(editor: vscode.TextEditor) {
  const key = editor.document.uri.toString();
  const current = globalStates.get(key) ?? "all";
  const doc = parseDocument(editor.document);
  if (current === "all") {
    await applyOverview(editor);
    globalStates.set(key, "overview");
    vscode.window.setStatusBarMessage("OVERVIEW", 1500);
  } else if (current === "overview") {
    // A fold range covers a whole subtree, so a parent's own body text can't be
    // hidden while its children stay visible. Only leaf entries get folded here.
    const states = statesFor(editor.document);
    states.clear();
    await vscode.commands.executeCommand("editor.unfoldAll");
    const leaves = doc.headings
      .filter((h) => !doc.headings.some((other) => other.parent === h.index))
      .filter((h) => lastContentLine(doc.lines, h.line, h.subtreeEnd) > h.line)
      .map((h) => h.line);
    await fold(leaves);
    leaves.forEach((line) => states.set(line, "folded"));
    globalStates.set(key, "contents");
    vscode.window.setStatusBarMessage("CONTENTS", 1500);
  } else {
    statesFor(editor.document).clear();
    await vscode.commands.executeCommand("editor.unfoldAll");
    globalStates.set(key, "all");
    vscode.window.setStatusBarMessage("SHOW ALL", 1500);
  }
}

/** Stops the startup overview hiding a line that something has just navigated to. */
export function markOpened(uri: vscode.Uri) {
  opened.add(uri.toString());
}

async function foldOnFirstOpen(editor: vscode.TextEditor | undefined) {
  if (!editor || editor.document.languageId !== "org" || !startupFolded()) {
    return;
  }
  const key = editor.document.uri.toString();
  if (opened.has(key)) {
    return;
  }
  opened.add(key);
  // VS Code computes fold ranges asynchronously after an editor appears.
  await new Promise((resolve) => setTimeout(resolve, 250));
  if (vscode.window.activeTextEditor?.document.uri.toString() !== key) {
    return;
  }
  await applyOverview(editor);
  globalStates.set(key, "overview");
}

export function activateLanguage(context: vscode.ExtensionContext) {
  const selector: vscode.DocumentSelector = { language: "org" };
  context.subscriptions.push(
    vscode.languages.registerFoldingRangeProvider(selector, folding),
    vscode.languages.registerDocumentSymbolProvider(selector, symbols),
    vscode.languages.registerDocumentLinkProvider(selector, links),
    vscode.commands.registerCommand("orgflow.org.followLink", followLink),
    vscode.window.onDidChangeActiveTextEditor(foldOnFirstOpen),
    vscode.workspace.onDidCloseTextDocument((document) => {
      opened.delete(document.uri.toString());
      subtreeStates.delete(document.uri.toString());
      globalStates.delete(document.uri.toString());
    }),
  );
  void foldOnFirstOpen(vscode.window.activeTextEditor);
}

export { resolveLink };
