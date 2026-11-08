// Agenda views as read-only virtual documents, so j, k, / and yank all work through
// VSCodeVim, with the org-agenda action keys bound only in that language.
import * as vscode from "vscode";
import { AgendaFile, AgendaLine, AgendaTarget, AgendaView, renderView } from "../org/agenda";
import { clockFromDate } from "../org/date";
import { readText, showFresh, writeText } from "./files";
import { markOpened, revealLine } from "./language";
import { agendaFiles, agendaViews, agendaWidth, deadlineWarningDays, orgConfig } from "./settings";
import { pickFromMenu, releaseKeys } from "./whichKey";

const SCHEME = "orgflow-agenda";

async function isDirectory(path: string): Promise<boolean> {
  try {
    const stat = await vscode.workspace.fs.stat(vscode.Uri.file(path));
    return (stat.type & vscode.FileType.Directory) !== 0;
  } catch {
    return false;
  }
}

/** Expands agenda entries as org does: directories aren't recursive, and dotfiles are out. */
export async function collectAgendaPaths(entries: string[]): Promise<string[]> {
  const seen = new Set<string>();
  const paths: string[] = [];
  const addPath = (path: string) => {
    if (!seen.has(path)) {
      seen.add(path);
      paths.push(path);
    }
  };
  for (const entry of entries) {
    if (await isDirectory(entry)) {
      const children = await vscode.workspace.fs.readDirectory(vscode.Uri.file(entry));
      children
        .filter(
          ([name, type]) =>
            (type & vscode.FileType.Directory) === 0 && /^[^.].*\.org$/.test(name),
        )
        .map(([name]) => name)
        .sort()
        .forEach((name) => addPath(`${entry.replace(/\/$/, "")}/${name}`));
    } else {
      addPath(entry);
    }
  }
  return paths;
}

async function loadFiles(): Promise<AgendaFile[]> {
  const paths = await collectAgendaPaths(agendaFiles());
  const files: AgendaFile[] = [];
  for (const path of paths) {
    const text = await readText(path);
    if (text !== null) {
      files.push({
        path,
        base: (path.split("/").pop() ?? path).replace(/\.org$/, ""),
        text,
      });
    }
  }
  return files;
}

class AgendaProvider implements vscode.TextDocumentContentProvider {
  private changes = new vscode.EventEmitter<vscode.Uri>();
  readonly onDidChange = this.changes.event;
  private rendered = new Map<string, AgendaLine[]>();
  private offsets = new Map<string, number>();

  async provideTextDocumentContent(uri: vscode.Uri): Promise<string> {
    const key = new URLSearchParams(uri.query).get("view");
    const view = agendaViews().find((v) => v.key === key);
    if (!view) {
      return `No agenda view with key "${key}"`;
    }
    let lines: AgendaLine[];
    try {
      lines = renderView(view, await loadFiles(), {
        config: orgConfig(),
        clock: clockFromDate(new Date()),
        width: agendaWidth(),
        weekOffset: this.offsets.get(uri.toString()) ?? 0,
        deadlineWarningDays: deadlineWarningDays(),
      });
    } catch (error) {
      return `Agenda view "${view.description}" failed: ${error instanceof Error ? error.message : String(error)}`;
    }
    this.rendered.set(uri.toString(), lines);
    return lines.map((line) => line.text).join("\n");
  }

  lineAt(uri: vscode.Uri, line: number): AgendaLine | undefined {
    return this.rendered.get(uri.toString())?.[line];
  }

  shiftWeek(uri: vscode.Uri, delta: number) {
    const key = uri.toString();
    this.offsets.set(key, (this.offsets.get(key) ?? 0) + delta);
    this.changes.fire(uri);
  }

  refresh(uri: vscode.Uri) {
    this.changes.fire(uri);
  }

  refreshAll() {
    for (const document of vscode.workspace.textDocuments) {
      if (document.uri.scheme === SCHEME) {
        this.changes.fire(document.uri);
      }
    }
  }
}

export const agendaProvider = new AgendaProvider();

function viewUri(view: AgendaView): vscode.Uri {
  const name = view.description.replace(/[^\w -]/g, "");
  return vscode.Uri.from({
    scheme: SCHEME,
    path: `/${name}.org-agenda`,
    query: `view=${encodeURIComponent(view.key)}`,
  });
}

function activeAgenda(): vscode.TextEditor | undefined {
  const editor = vscode.window.activeTextEditor;
  return editor?.document.uri.scheme === SCHEME ? editor : undefined;
}

export function agendaTargetAtCursor(): AgendaTarget | undefined {
  const editor = activeAgenda();
  if (!editor) {
    return undefined;
  }
  return agendaProvider.lineAt(editor.document.uri, editor.selection.active.line)?.target;
}

/** Runs an edit on the file behind an agenda line, refusing if that line has changed. */
export async function editAgendaTarget(
  target: AgendaTarget,
  edit: (text: string, line: number) => string | null,
): Promise<boolean> {
  const text = await readText(target.path);
  if (text === null) {
    vscode.window.showWarningMessage(`Can't read ${target.path}`);
    return false;
  }
  if (text.split("\n")[target.line] !== target.raw) {
    vscode.window.showWarningMessage("That file has changed. Refreshing the agenda, so try again.");
    agendaProvider.refreshAll();
    return false;
  }
  const after = edit(text, target.line);
  if (after === null) {
    return false;
  }
  await writeText(target.path, after);
  agendaProvider.refreshAll();
  return true;
}

async function openAgenda() {
  const views = agendaViews();
  const node = await pickFromMenu(
    {
      key: "",
      name: "",
      children: views.map((view) => ({
        key: view.key,
        name: view.description,
        command: view.key,
      })),
    },
    "Agenda",
  );
  await releaseKeys();
  const view = views.find((v) => v.key === node?.command);
  if (view) {
    const document = await vscode.workspace.openTextDocument(viewUri(view));
    await vscode.languages.setTextDocumentLanguage(document, "org-agenda");
    await vscode.window.showTextDocument(document, { preview: false });
  }
}

async function jumpToTarget(beside: boolean) {
  const target = agendaTargetAtCursor();
  if (!target) {
    return;
  }
  markOpened(vscode.Uri.file(target.path));
  const editor = await showFresh(target.path, {
    viewColumn: beside ? vscode.ViewColumn.Beside : undefined,
  });
  await revealLine(editor, target.line);
}

export function activateAgenda(context: vscode.ExtensionContext) {
  const shift = (delta: number) => () => {
    const editor = activeAgenda();
    if (editor) {
      agendaProvider.shiftWeek(editor.document.uri, delta);
    }
  };
  context.subscriptions.push(
    vscode.workspace.registerTextDocumentContentProvider(SCHEME, agendaProvider),
    vscode.commands.registerCommand("orgflow.agenda", openAgenda),
    vscode.commands.registerCommand("orgflow.agenda.open", () => jumpToTarget(false)),
    vscode.commands.registerCommand("orgflow.agenda.openBeside", () => jumpToTarget(true)),
    vscode.commands.registerCommand("orgflow.agenda.refresh", () => {
      const editor = activeAgenda();
      if (editor) {
        agendaProvider.refresh(editor.document.uri);
      }
    }),
    vscode.commands.registerCommand("orgflow.agenda.quit", () =>
      vscode.commands.executeCommand("workbench.action.closeActiveEditor"),
    ),
    vscode.commands.registerCommand("orgflow.agenda.later", shift(1)),
    vscode.commands.registerCommand("orgflow.agenda.earlier", shift(-1)),
    vscode.workspace.onDidSaveTextDocument((document) => {
      if (document.languageId === "org") {
        agendaProvider.refreshAll();
      }
    }),
  );
}
