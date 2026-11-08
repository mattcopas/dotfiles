// Reading and changing org files. Text is always handled with LF internally, and
// a change is applied as the smallest span, so VS Code keeps the file's own line
// endings and unsaved edits in an open editor are never overwritten.
import * as vscode from "vscode";
import { minimalEdit } from "../org/edits";

export function normalized(document: vscode.TextDocument): string {
  return document.getText().replace(/\r\n/g, "\n");
}

function openDocument(path: string): vscode.TextDocument | undefined {
  return vscode.workspace.textDocuments.find(
    (document) => !document.isClosed && document.uri.fsPath === path,
  );
}

/**
 * A file's current text. Unsaved editor contents win, but a clean document is read
 * from disk: VS Code keeps closed documents cached and only notices outside changes
 * after a delay, so trusting a clean one could save old text over a `git pull`.
 */
export async function readText(path: string): Promise<string | null> {
  const open = openDocument(path);
  if (open?.isDirty) {
    return normalized(open);
  }
  try {
    const bytes = await vscode.workspace.fs.readFile(vscode.Uri.file(path));
    return Buffer.from(bytes).toString("utf8").replace(/\r\n/g, "\n");
  } catch {
    return open ? normalized(open) : null;
  }
}

function positionOf(text: string, offset: number): vscode.Position {
  let line = 0;
  let lineStart = 0;
  for (
    let at = text.indexOf("\n");
    at !== -1 && at < offset;
    at = text.indexOf("\n", at + 1)
  ) {
    line++;
    lineStart = at + 1;
  }
  return new vscode.Position(line, offset - lineStart);
}

/** Applies new text to a document as the smallest possible edit. */
export async function replaceInDocument(
  document: vscode.TextDocument,
  after: string,
): Promise<boolean> {
  const before = normalized(document);
  const change = minimalEdit(before, after);
  if (!change) {
    return true;
  }
  const edit = new vscode.WorkspaceEdit();
  edit.replace(
    document.uri,
    new vscode.Range(
      positionOf(before, change.start),
      positionOf(before, change.end),
    ),
    change.text,
  );
  return vscode.workspace.applyEdit(edit);
}

/**
 * Writes a file. A document with unsaved work is edited in place and stays unsaved,
 * so that save remains the user's. Anything else goes straight to disk: org files
 * usually sit outside the workspace, where VS Code doesn't watch for outside changes,
 * so saving through a cached document could fail or bring back old text.
 */
export async function writeText(path: string, after: string): Promise<void> {
  const open = openDocument(path);
  if (open?.isDirty) {
    if (!(await replaceInDocument(open, after))) {
      throw new Error(`Couldn't update ${path}`);
    }
    return;
  }
  const uri = vscode.Uri.file(path);
  let crlf = open?.eol === vscode.EndOfLine.CRLF;
  try {
    const raw = Buffer.from(await vscode.workspace.fs.readFile(uri)).toString("utf8");
    crlf = raw.includes("\r\n");
  } catch {
    await vscode.workspace.fs.createDirectory(vscode.Uri.joinPath(uri, ".."));
  }
  const text = crlf ? after.replace(/\n/g, "\r\n") : after;
  await vscode.workspace.fs.writeFile(uri, Buffer.from(text, "utf8"));
}

/** Opens a file in an editor, making sure a clean cached document isn't behind the disk. */
export async function showFresh(
  path: string,
  options: vscode.TextDocumentShowOptions = {},
): Promise<vscode.TextEditor> {
  const uri = vscode.Uri.file(path);
  const document = await vscode.workspace.openTextDocument(uri);
  const editor = await vscode.window.showTextDocument(document, { preview: false, ...options });
  if (!document.isDirty) {
    const disk = await readText(path);
    if (disk !== null && disk !== normalized(document)) {
      await vscode.commands.executeCommand("workbench.action.files.revert");
    }
  }
  return editor;
}
