// Runs inside a real VS Code through test/run-integration.sh. The VS Code CLI exits 0
// even when these throw, so the script reads a result file written at the end.
import assert from "node:assert/strict";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import * as vscode from "vscode";
import { clockFromDate, formatDate, orgDate } from "../org/date";

const root = process.env.ORGFLOW_TEST_ROOT as string;
const resultFile = process.env.ORGFLOW_TEST_RESULT as string;
const today = clockFromDate(new Date()).today;

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

async function until<T>(read: () => T | undefined | false, what: string, ms = 5000): Promise<T> {
  const start = Date.now();
  for (;;) {
    const value = read();
    if (value) {
      return value;
    }
    if (Date.now() - start > ms) {
      throw new Error(`Timed out waiting for ${what}`);
    }
    await sleep(50);
  }
}

const results: string[] = [];

async function test(name: string, body: () => Promise<void>) {
  await vscode.commands.executeCommand("workbench.action.closeAllEditors");
  try {
    await body();
    results.push(`ok ${name}`);
  } catch (error) {
    results.push(`FAILED ${name}: ${error instanceof Error ? error.message : String(error)}`);
  }
}

function write(relative: string, text: string): string {
  const path = join(root, relative);
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, text);
  return path;
}

async function open(path: string, line = 0) {
  const document = await vscode.workspace.openTextDocument(vscode.Uri.file(path));
  const editor = await vscode.window.showTextDocument(document, { preview: false });
  const position = new vscode.Position(line, 0);
  editor.selection = new vscode.Selection(position, position);
  return editor;
}

const hidden = (editor: vscode.TextEditor, line: number) =>
  !editor.visibleRanges.some((r) => r.start.line <= line && line <= r.end.line);

const FOLD_DOC = [
  "* One",
  "Body of one.",
  "** Child a",
  "Body a.",
  "** Child b",
  "Body b.",
  "* Two",
  "Body of two.",
  "",
].join("\n");

export async function run(): Promise<void> {
  const extension = vscode.extensions.getExtension("mcopas-local.orgflow");
  assert.ok(extension, "extension is installed");
  await extension.activate();

  const config = vscode.workspace.getConfiguration("orgflow");
  await config.update("agenda.files", [join(root, "agenda")], vscode.ConfigurationTarget.Global);
  await config.update("journal.directory", join(root, "journal"), vscode.ConfigurationTarget.Global);
  await config.update(
    "capture.templates",
    [
      { key: "w", description: "Work" },
      { key: "ww", description: "Plain", file: join(root, "agenda", "todo.org"), headline: "Todo list", prepend: true },
      { key: "wt", description: "Today", file: join(root, "agenda", "todo.org"), headline: "Todo list", prepend: true, schedule: "+0d" },
      { key: "n", description: "New", file: join(root, "fresh", "dir", "new.org"), headline: "Todo list" },
    ],
    vscode.ConfigurationTarget.Global,
  );
  await config.update("startupFolded", false, vscode.ConfigurationTarget.Global);

  await test("org language and theme are registered", async () => {
    const editor = await open(write("lang.org", "* TODO x\n"));
    assert.equal(editor.document.languageId, "org");
    await vscode.workspace.getConfiguration("workbench").update("colorTheme", "Doom One", vscode.ConfigurationTarget.Global);
    const themes = extension.packageJSON.contributes.themes;
    assert.equal(themes[0].label, "Doom One");
    assert.ok(existsSync(join(extension.extensionPath, themes[0].path)));
  });

  await test("outline symbols nest", async () => {
    const editor = await open(write("sym.org", FOLD_DOC));
    const found = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>(
      "vscode.executeDocumentSymbolProvider",
      editor.document.uri,
    );
    assert.deepEqual(found.map((s) => s.name), ["One", "Two"]);
    assert.deepEqual(found[0].children.map((s) => s.name), ["Child a", "Child b"]);
  });

  await test("TAB cycles a subtree through folded, children, subtree", async () => {
    const editor = await open(write("fold.org", FOLD_DOC));
    await sleep(800);
    await vscode.commands.executeCommand("orgflow.org.cycle");
    await until(() => hidden(editor, 1), "folded");
    assert.ok(!hidden(editor, 6), "next heading stays visible");

    await vscode.commands.executeCommand("orgflow.org.cycle");
    await until(() => !hidden(editor, 1), "children");
    assert.ok(!hidden(editor, 2) && !hidden(editor, 4), "child headings visible");
    await until(() => hidden(editor, 3) && hidden(editor, 5), "child bodies hidden");

    await vscode.commands.executeCommand("orgflow.org.cycle");
    await until(() => !hidden(editor, 3) && !hidden(editor, 5), "subtree");

    await vscode.commands.executeCommand("orgflow.org.cycle");
    await until(() => hidden(editor, 1), "folded again");
  });

  await test("TAB expands children that have children and plain bodies", async () => {
    const doc = [
      "#+TITLE: Demo",
      "",
      "* Todo list :work:",
      "** TODO [#A] Fix the *bold* bug",
      "SCHEDULED: <2026-11-08 Sun>",
      "Some text.",
      "** IN PROGRESS Second task",
      "- a list item",
      "| name | qty |",
      "* Notes",
      "** Reference",
      "#+BEGIN_SRC python",
      "x = 1",
      "#+END_SRC",
      "",
    ].join("\n");
    const editor = await open(write("fold2.org", doc), 2);
    await sleep(800);
    const seen = () => [3, 5, 6, 7, 8, 9].map((line) => `${line}:${hidden(editor, line) ? "h" : "v"}`).join(" ");
    await vscode.commands.executeCommand("orgflow.org.globalCycle");
    await until(() => hidden(editor, 3), "overview");
    editor.selection = new vscode.Selection(2, 2, 2, 2);
    await sleep(200);
    await vscode.commands.executeCommand("orgflow.org.cycle");
    await until(() => !hidden(editor, 3) && hidden(editor, 5), `children, saw ${seen()}`);
    await sleep(300);
    await vscode.commands.executeCommand("orgflow.org.cycle");
    await sleep(600);
    assert.ok(!hidden(editor, 5) && !hidden(editor, 7), `subtree should show bodies, saw ${seen()}`);
  });

  await test("S-TAB cycles overview, contents, show all", async () => {
    const editor = await open(write("global.org", FOLD_DOC));
    await sleep(800);
    await vscode.commands.executeCommand("orgflow.org.globalCycle");
    await until(() => hidden(editor, 1) && hidden(editor, 7), "overview");
    assert.ok(!hidden(editor, 6));
    await vscode.commands.executeCommand("orgflow.org.globalCycle");
    await until(() => !hidden(editor, 2) && hidden(editor, 3), "contents");
    await vscode.commands.executeCommand("orgflow.org.globalCycle");
    await until(() => !hidden(editor, 3) && !hidden(editor, 7), "show all");
  });

  await test("startup folding shows top-level headings only", async () => {
    await config.update("startupFolded", true, vscode.ConfigurationTarget.Global);
    const editor = await open(write("startup.org", FOLD_DOC));
    await until(() => hidden(editor, 1) && hidden(editor, 7), "startup overview");
    await config.update("startupFolded", false, vscode.ConfigurationTarget.Global);
  });

  await test("setting a TODO edits the document without saving it", async () => {
    const path = write("todo.org", "* TODO x\nBody\n");
    const editor = await open(path, 1);
    await vscode.commands.executeCommand("orgflow.org.setTodo", "IN PROGRESS");
    assert.equal(editor.document.getText(), "* IN PROGRESS x\nBody\n");
    assert.ok(editor.document.isDirty);
    assert.equal(readFileSync(path, "utf8"), "* TODO x\nBody\n");
    await vscode.commands.executeCommand("workbench.action.files.revert");
  });

  await test("schedule commands write planning lines", async () => {
    const editor = await open(write("sched.org", "* TODO x\n"));
    await vscode.commands.executeCommand("orgflow.org.scheduleTomorrow");
    assert.equal(editor.document.getText(), `* TODO x\nSCHEDULED: <${orgDate(today + 1)}>\n`);
    await vscode.commands.executeCommand("orgflow.org.scheduleToday");
    assert.equal(editor.document.getText(), `* TODO x\nSCHEDULED: <${orgDate(today)}>\n`);
    await vscode.commands.executeCommand("workbench.action.files.revert");
  });

  await test("moving a subtree keeps the cursor on it", async () => {
    const editor = await open(write("move.org", "* a\nbody\n* b\n"));
    await vscode.commands.executeCommand("orgflow.org.moveDown");
    assert.equal(editor.document.getText(), "* b\n* a\nbody\n");
    assert.equal(editor.selection.active.line, 1);
    await vscode.commands.executeCommand("orgflow.org.promote");
    await vscode.commands.executeCommand("orgflow.org.demote");
    assert.equal(editor.document.getText(), "* b\n** a\nbody\n");
    await vscode.commands.executeCommand("workbench.action.files.revert");
  });

  await test("a capture to a CRLF file keeps its line endings", async () => {
    const path = write("agenda/todo.org", "* Todo list\r\n** TODO Old\r\n");
    await vscode.commands.executeCommand("orgflow.capture", "ww", "New");
    assert.equal(readFileSync(path, "utf8"), "* Todo list\r\n** TODO New\r\n** TODO Old\r\n");
  });

  await test("a CRLF file keeps its line endings through an edit", async () => {
    const path = write("crlf.org", "* TODO x\r\nBody\r\n* TODO y\r\n");
    const editor = await open(path, 2);
    await vscode.commands.executeCommand("orgflow.org.setTodo", "DONE");
    await editor.document.save();
    assert.equal(readFileSync(path, "utf8"), "* TODO x\r\nBody\r\n* DONE y\r\n");
  });

  await test("table TAB aligns and moves, adding a row at the end", async () => {
    const editor = await open(write("table.org", "| a | bb |\n| ccc | d |\n"));
    editor.selection = new vscode.Selection(0, 2, 0, 2);
    await vscode.commands.executeCommand("orgflow.org.cycle");
    assert.equal(editor.document.getText(), "| a   | bb |\n| ccc | d  |\n");
    assert.equal(editor.selection.active.character, 8);
    editor.selection = new vscode.Selection(1, 8, 1, 8);
    await vscode.commands.executeCommand("orgflow.org.cycle");
    assert.equal(editor.document.lineAt(2).text, "|     |    |");
    assert.equal(editor.selection.active.line, 2);
    await vscode.commands.executeCommand("workbench.action.files.revert");
  });

  await test("links are found and internal ones resolve", async () => {
    const path = write("links.org", "See [[*Target][the target]] and https://example.com\n* Target\n");
    const editor = await open(path);
    const links = await vscode.commands.executeCommand<vscode.DocumentLink[]>(
      "vscode.executeLinkProvider",
      editor.document.uri,
    );
    assert.equal(links.length, 2);
    editor.selection = new vscode.Selection(0, 8, 0, 8);
    await vscode.commands.executeCommand("orgflow.org.openLink");
    await until(() => vscode.window.activeTextEditor?.selection.active.line === 1, "jump to heading");
  });

  await test("capture prepends under its headline and saves", async () => {
    const path = write("agenda/todo.org", "#+FILETAGS: :work:\n* Todo list\n** TODO Existing\n");
    await vscode.commands.executeCommand("orgflow.capture", "ww", "From the test");
    assert.equal(
      readFileSync(path, "utf8"),
      "#+FILETAGS: :work:\n* Todo list\n** TODO From the test\n** TODO Existing\n",
    );
  });

  await test("capture leaves unsaved work in an open file unsaved", async () => {
    const path = write("agenda/todo.org", "* Todo list\n** TODO Existing\n");
    const editor = await open(path);
    await vscode.commands.executeCommand("workbench.action.files.revert");
    await until(() => editor.document.getText() === "* Todo list\n** TODO Existing\n", "editor to show the file");
    await editor.edit((edit) => edit.insert(new vscode.Position(1, 0), "** TODO Unsaved\n"));
    assert.ok(editor.document.isDirty);
    await vscode.commands.executeCommand("orgflow.capture", "ww", "Captured");
    assert.equal(
      editor.document.getText(),
      "* Todo list\n** TODO Captured\n** TODO Unsaved\n** TODO Existing\n",
    );
    assert.ok(editor.document.isDirty, "still unsaved");
    assert.equal(readFileSync(path, "utf8"), "* Todo list\n** TODO Existing\n");
    await vscode.commands.executeCommand("workbench.action.files.revert");
  });

  await test("capture with a schedule, and into a file that doesn't exist yet", async () => {
    const path = write("agenda/todo.org", "* Todo list\n");
    await vscode.commands.executeCommand("orgflow.capture", "wt", "Sched");
    assert.equal(readFileSync(path, "utf8"), `* Todo list\n** TODO Sched \n SCHEDULED: <${orgDate(today)}>\n`);
    await vscode.commands.executeCommand("orgflow.capture", "n", "Fresh");
    assert.equal(readFileSync(join(root, "fresh/dir/new.org"), "utf8"), "* Todo list\n** TODO Fresh\n");
  });

  await test("agenda views through their virtual document", async () => {
    const path = write(
      "agenda/todo.org",
      `#+FILETAGS: :work:\n* Todo list\n** TODO [#A] Urgent\n** TODO Scheduled item\nSCHEDULED: <${orgDate(today)}>\n`,
    );
    write("agenda/.hidden.org", `* TODO Hidden\nSCHEDULED: <${orgDate(today)}>\n`);
    const uri = vscode.Uri.from({ scheme: "orgflow-agenda", path: "/Work agenda view.org-agenda", query: "view=w" });
    const document = await vscode.workspace.openTextDocument(uri);
    await vscode.languages.setTextDocumentLanguage(document, "org-agenda");
    const editor = await vscode.window.showTextDocument(document, { preview: false });
    const text = document.getText();
    assert.match(text, /High priority unfinished tasks\n  todo:\s+TODO \[#A\] Urgent/);
    assert.match(text, /Today's tasks\n  todo:\s+TODO Scheduled item/);
    assert.ok(!text.includes("Hidden"), "dotfiles stay off the agenda");
    assert.equal(document.languageId, "org-agenda");

    // Act on the urgent item.
    const urgent = text.split("\n").findIndex((line) => line.includes("Urgent"));
    editor.selection = new vscode.Selection(urgent, 0, urgent, 0);
    await vscode.commands.executeCommand("orgflow.org.setTodo", "WAIT");
    assert.match(readFileSync(path, "utf8"), /\*\* WAIT \[#A\] Urgent/);
    await until(() => !document.getText().includes("TODO [#A] Urgent"), "agenda refresh");

    // Schedule from the agenda, with the cursor on another item.
    const scheduled = document.getText().split("\n").findIndex((line) => line.includes("Scheduled item"));
    editor.selection = new vscode.Selection(scheduled, 0, scheduled, 0);
    await vscode.commands.executeCommand("orgflow.org.scheduleTomorrow");
    assert.match(readFileSync(path, "utf8"), new RegExp(`Scheduled item\\nSCHEDULED: <${orgDate(today + 1)}>`));
    await until(() => /Tomorrow's tasks\n  todo:\s+TODO Scheduled item/.test(document.getText()), "moved to tomorrow");
  });

  await test("a stale agenda line refuses to edit the wrong heading", async () => {
    const path = write("agenda/todo.org", "#+FILETAGS: :work:\n* Todo list\n** TODO First\n** TODO Second\n");
    const uri = vscode.Uri.from({ scheme: "orgflow-agenda", path: "/Stale.org-agenda", query: "view=w" });
    const document = await vscode.workspace.openTextDocument(uri);
    const editor = await vscode.window.showTextDocument(document, { preview: false });
    const line = document.getText().split("\n").findIndex((l) => l.includes("Second"));
    editor.selection = new vscode.Selection(line, 0, line, 0);
    const changed = "#+FILETAGS: :work:\n* Todo list\n** TODO Inserted\n** TODO First\n** TODO Second\n";
    writeFileSync(path, changed);
    await vscode.commands.executeCommand("orgflow.org.setTodo", "DONE");
    assert.equal(readFileSync(path, "utf8"), changed, "nothing was edited");
  });

  await test("Enter on an agenda line jumps to the heading", async () => {
    const path = write("agenda/todo.org", "#+FILETAGS: :work:\n* Todo list\n** TODO Jump here\n");
    const uri = vscode.Uri.from({ scheme: "orgflow-agenda", path: "/Jump.org-agenda", query: "view=w" });
    const document = await vscode.workspace.openTextDocument(uri);
    const editor = await vscode.window.showTextDocument(document, { preview: false });
    const line = document.getText().split("\n").findIndex((l) => l.includes("Jump here"));
    editor.selection = new vscode.Selection(line, 0, line, 0);
    await vscode.commands.executeCommand("orgflow.agenda.open");
    const target = await until(
      () => vscode.window.activeTextEditor?.document.uri.fsPath === path && vscode.window.activeTextEditor,
      "the org file",
    );
    assert.equal(target.selection.active.line, 2);
    await until(() => target.document.lineAt(2).text === "** TODO Jump here", "fresh file contents");
  });

  await test("journal: new file, entry, then carryover across a month", async () => {
    const name = formatDate("%b-%Y.org", today);
    const previousAbs = today - 40;
    const previousName = formatDate("%b-%Y.org", previousAbs);
    const stamp = formatDate("%Y%m%d", previousAbs);
    const previous = write(
      `journal/${previousName}`,
      `* ${formatDate("%a %e %b %Y", previousAbs)}\n:PROPERTIES:\n:CREATED:  ${stamp}\n:END:\n** TODO 09:00 Carry me\n** 10:00 Stay here\n`,
    );
    await vscode.commands.executeCommand("orgflow.journal.newEntry");
    const path = join(root, "journal", name);
    const text = readFileSync(path, "utf8");
    assert.ok(text.startsWith(`* ${formatDate("%a %e %b %Y", today)}\n:PROPERTIES:\n:CREATED:  ${formatDate("%Y%m%d", today)}\n:END:\n** TODO 09:00 Carry me\n** `), text);
    assert.ok(!readFileSync(previous, "utf8").includes("Carry me"), "moved out of the old file");
    assert.ok(readFileSync(previous, "utf8").includes("Stay here"));
    const editor = await until(
      () => vscode.window.activeTextEditor?.document.uri.fsPath === path && vscode.window.activeTextEditor,
      "journal editor",
    );
    const cursorLine = editor.document.lineAt(editor.selection.active.line).text;
    assert.match(cursorLine, /^\*\* \d\d:\d\d $/);
    assert.equal(editor.selection.active.character, cursorLine.length);
  });

  await test("every menu command exists", async () => {
    const commands = new Set(await vscode.commands.getCommands(true));
    const missing: string[] = [];
    const visit = (nodes: { command?: string; children?: never[] }[]) => {
      for (const node of nodes) {
        if (node.command && !commands.has(node.command) && !node.command.startsWith("magit.")) {
          missing.push(node.command);
        }
        if (node.children) {
          visit(node.children);
        }
      }
    };
    visit(vscode.workspace.getConfiguration("orgflow").get("whichKey.menu", []));
    assert.deepEqual(missing, []);
  });

  await test("every keybinding command exists", async () => {
    const commands = new Set(await vscode.commands.getCommands(true));
    const bindings: { command: string }[] = extension.packageJSON.contributes.keybindings;
    assert.deepEqual(bindings.map((b) => b.command).filter((c) => !commands.has(c)), []);
  });

  writeFileSync(resultFile, `${results.join("\n")}\nDONE\n`);
}
