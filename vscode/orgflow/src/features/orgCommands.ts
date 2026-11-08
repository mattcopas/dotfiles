// Commands that act on "the current heading", which is either the heading around
// the cursor in an org file or the item under the cursor in an agenda.
import * as vscode from "vscode";
import { filterMenu, MenuNode } from "../keySequence";
import { clockFromDate } from "../org/date";
import {
  changePriority,
  moveSubtree,
  setPlanning,
  setTags,
  setTodo,
  shiftHeading,
  shiftPlanning,
  shiftSubtree,
} from "../org/edits";
import { headingAt, parseHeadingLine } from "../org/parser";
import { alignTableAt, blankRow, isTableLine, nextCell } from "../org/table";
import { parseDateInput } from "../org/timestamp";
import { agendaProvider, agendaTargetAtCursor, editAgendaTarget } from "./agenda";
import { normalized, replaceInDocument } from "./files";
import {
  cycleGlobal,
  cycleHeading,
  linkAtCursor,
  parseDocument,
} from "./language";
import { orgConfig } from "./settings";
import { pickFromMenu, releaseKeys } from "./whichKey";

type Edit = (text: string, line: number) => string | null;

function orgEditor(): vscode.TextEditor | undefined {
  const editor = vscode.window.activeTextEditor;
  return editor?.document.languageId === "org" ? editor : undefined;
}

function moveCursor(editor: vscode.TextEditor, line: number, column: number) {
  const position = new vscode.Position(line, column);
  editor.selection = new vscode.Selection(position, position);
}

function report(error: unknown) {
  vscode.window.setStatusBarMessage(
    error instanceof Error ? error.message : String(error),
    3000,
  );
}

/** Applies an edit to the heading under the cursor, in whichever kind of editor. */
async function editCurrentHeading(edit: Edit): Promise<void> {
  try {
    const target = agendaTargetAtCursor();
    if (target) {
      await editAgendaTarget(target, edit);
      return;
    }
    const editor = orgEditor();
    if (!editor) {
      vscode.window.setStatusBarMessage("Not on an org heading", 2000);
      return;
    }
    const heading = headingAt(parseDocument(editor.document), editor.selection.active.line);
    if (!heading) {
      vscode.window.setStatusBarMessage("Before the first heading", 2000);
      return;
    }
    const after = edit(normalized(editor.document), heading.line);
    if (after !== null) {
      await replaceInDocument(editor.document, after);
    }
  } catch (error) {
    report(error);
  }
}

function now() {
  return clockFromDate(new Date());
}

function keywordMenu(): MenuNode {
  const config = orgConfig();
  const children: MenuNode[] = config.sequences.flatMap((sequence) =>
    [...sequence.todo, ...sequence.done].map((name) => ({
      key: config.keys.get(name) ?? "",
      name,
      command: name,
    })),
  );
  children.push({ key: " ", name: "Clear keyword", command: "" });
  return { key: "", name: "", children };
}

async function setTodoCommand(keyword?: string) {
  let chosen: string | null;
  if (typeof keyword === "string") {
    chosen = keyword;
  } else {
    const node = await pickFromMenu(filterMenu(keywordMenu(), undefined), "TODO state");
    await releaseKeys();
    if (!node) {
      return;
    }
    chosen = node.command === "" ? null : (node.command as string);
  }
  await editCurrentHeading((text, line) => setTodo(text, line, chosen, orgConfig(), now()));
}

async function scheduleOn(label: "SCHEDULED" | "DEADLINE", input: string) {
  const parsed = parseDateInput(input, now().today);
  if (!parsed) {
    vscode.window.showWarningMessage(`Can't read the date "${input}"`);
    return;
  }
  await editCurrentHeading((text, line) =>
    setPlanning(text, line, label, parsed.abs, parsed.minutes, orgConfig()),
  );
}

async function promptSchedule(label: "SCHEDULED" | "DEADLINE") {
  const input = await vscode.window.showInputBox({
    title: label === "SCHEDULED" ? "Schedule for" : "Deadline",
    placeHolder: "+1d, fri, 2026-11-12, 12-25, tomorrow 14:30",
    validateInput: (value) =>
      parseDateInput(value, now().today) ? null : "Try +1d, fri, 2026-11-12 or tomorrow 14:30",
  });
  if (input !== undefined) {
    await scheduleOn(label, input);
  }
}

async function setTagsCommand() {
  const editor = orgEditor();
  if (!editor) {
    return;
  }
  const heading = headingAt(parseDocument(editor.document), editor.selection.active.line);
  if (!heading) {
    return;
  }
  const value = await vscode.window.showInputBox({
    title: "Tags",
    placeHolder: "work:client",
    value: heading.localTags.join(":"),
  });
  if (value === undefined) {
    return;
  }
  const tags = value.split(/[:\s]+/).filter(Boolean);
  await editCurrentHeading((text, line) => setTags(text, line, tags, orgConfig()));
}

async function structureCommand(
  fallback: string | null,
  run: (text: string, line: number) => { text: string; line: number } | string,
) {
  const editor = orgEditor();
  if (!editor) {
    return;
  }
  const { line, character } = editor.selection.active;
  const onHeading = !!parseHeadingLine(editor.document.lineAt(line).text, orgConfig());
  if (!onHeading) {
    // Off a heading, Alt+j and Alt+k drag the line, as org-metadown does on plain text.
    if (fallback) {
      await vscode.commands.executeCommand(fallback);
    }
    return;
  }
  try {
    const result = run(normalized(editor.document), line);
    if (typeof result === "string") {
      await replaceInDocument(editor.document, result);
      const shift = result.split("\n")[line].length - editor.document.lineAt(line).text.length;
      moveCursor(editor, line, Math.max(0, character + shift));
    } else {
      await replaceInDocument(editor.document, result.text);
      moveCursor(editor, result.line, character);
    }
  } catch (error) {
    report(error);
  }
}

async function tableTab(editor: vscode.TextEditor) {
  const { line, character } = editor.selection.active;
  const before = normalized(editor.document);
  const lines = alignTableAt(before, line).split("\n");
  const next = nextCell(lines, line, character);
  if (next.addRow) {
    lines.splice(next.line, 0, blankRow(lines[line]));
    next.column = 2;
  }
  await replaceInDocument(editor.document, lines.join("\n"));
  moveCursor(editor, next.line, next.column);
}

async function cycle() {
  const editor = orgEditor();
  if (!editor) {
    return;
  }
  const { line } = editor.selection.active;
  if (isTableLine(editor.document.lineAt(line).text)) {
    await tableTab(editor);
    return;
  }
  const doc = parseDocument(editor.document);
  const heading = doc.headings.find((h) => h.line === line);
  if (heading) {
    await cycleHeading(editor, heading, doc);
    return;
  }
  if (/^\s*(#\+begin_|:(PROPERTIES|LOGBOOK):)/i.test(doc.lines[line])) {
    await vscode.commands.executeCommand("editor.toggleFold");
  }
}

async function insertLink() {
  const editor = orgEditor();
  if (!editor) {
    return;
  }
  const target = await vscode.window.showInputBox({
    title: "Link",
    placeHolder: "https://example.com, file:notes.org, or *Heading",
  });
  if (!target) {
    return;
  }
  const description = await vscode.window.showInputBox({
    title: "Description (optional)",
  });
  if (description === undefined) {
    return;
  }
  const text = description ? `[[${target}][${description}]]` : `[[${target}]]`;
  await editor.edit((edit) => edit.insert(editor.selection.active, text));
}

async function openLinkAtCursor() {
  const editor = orgEditor();
  const link = editor && linkAtCursor(editor);
  if (editor && link) {
    await vscode.commands.executeCommand(
      "orgflow.org.followLink",
      editor.document.uri.toString(),
      link.target,
    );
  }
}

function updateContext(editor: vscode.TextEditor | undefined) {
  const isOrg = editor?.document.languageId === "org";
  const line = isOrg && editor ? editor.document.lineAt(editor.selection.active.line).text : "";
  void vscode.commands.executeCommand("setContext", "orgflow.inTable", isOrg && isTableLine(line));
  void vscode.commands.executeCommand(
    "setContext",
    "orgflow.onLink",
    !!(isOrg && editor && linkAtCursor(editor)),
  );
}

async function shiftAgendaDate(days: number) {
  const target = agendaTargetAtCursor();
  if (!target) {
    return;
  }
  if (target.kind !== "scheduled" && target.kind !== "deadline") {
    vscode.window.setStatusBarMessage("This item has no scheduled date or deadline here", 2000);
    return;
  }
  const label = target.kind === "scheduled" ? "SCHEDULED" : "DEADLINE";
  await editAgendaTarget(target, (text, line) =>
    shiftPlanning(text, line, label, days, orgConfig()),
  );
}

export function activateOrgCommands(context: vscode.ExtensionContext) {
  const register = (id: string, handler: (...args: never[]) => unknown) =>
    vscode.commands.registerCommand(id, handler);
  context.subscriptions.push(
    register("orgflow.org.setTodo", setTodoCommand),
    register("orgflow.org.schedule", () => promptSchedule("SCHEDULED")),
    register("orgflow.org.scheduleToday", () => scheduleOn("SCHEDULED", "+0d")),
    register("orgflow.org.scheduleTomorrow", () => scheduleOn("SCHEDULED", "+1d")),
    register("orgflow.org.deadline", () => promptSchedule("DEADLINE")),
    register("orgflow.org.setTags", setTagsCommand),
    register("orgflow.org.priorityUp", () =>
      editCurrentHeading((text, line) => changePriority(text, line, "up", orgConfig())),
    ),
    register("orgflow.org.priorityDown", () =>
      editCurrentHeading((text, line) => changePriority(text, line, "down", orgConfig())),
    ),
    register("orgflow.org.cycle", cycle),
    register("orgflow.org.globalCycle", () => {
      const editor = orgEditor();
      return editor ? cycleGlobal(editor) : undefined;
    }),
    register("orgflow.org.moveDown", () =>
      structureCommand("editor.action.moveLinesDownAction", (text, line) =>
        moveSubtree(text, line, "down", orgConfig()),
      ),
    ),
    register("orgflow.org.moveUp", () =>
      structureCommand("editor.action.moveLinesUpAction", (text, line) =>
        moveSubtree(text, line, "up", orgConfig()),
      ),
    ),
    register("orgflow.org.promote", () =>
      structureCommand(null, (text, line) => shiftHeading(text, line, -1, orgConfig())),
    ),
    register("orgflow.org.demote", () =>
      structureCommand(null, (text, line) => shiftHeading(text, line, 1, orgConfig())),
    ),
    register("orgflow.org.promoteSubtree", () =>
      structureCommand(null, (text, line) => shiftSubtree(text, line, -1, orgConfig())),
    ),
    register("orgflow.org.demoteSubtree", () =>
      structureCommand(null, (text, line) => shiftSubtree(text, line, 1, orgConfig())),
    ),
    register("orgflow.org.insertLink", insertLink),
    register("orgflow.org.openLink", openLinkAtCursor),
    register("orgflow.org.alignTable", async () => {
      const editor = orgEditor();
      if (editor) {
        await replaceInDocument(
          editor.document,
          alignTableAt(normalized(editor.document), editor.selection.active.line),
        );
      }
    }),
    register("orgflow.agenda.dateEarlier", () => shiftAgendaDate(-1)),
    register("orgflow.agenda.dateLater", () => shiftAgendaDate(1)),
    vscode.window.onDidChangeTextEditorSelection((event) => updateContext(event.textEditor)),
    vscode.window.onDidChangeActiveTextEditor(updateContext),
  );
  updateContext(vscode.window.activeTextEditor);
  void agendaProvider;
}
