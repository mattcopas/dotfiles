// SPC p p: find repositories, open one, then go straight to find-file, as your
// project.el setup does with project-switch-commands set to project-find-file.
import { homedir } from "node:os";
import * as vscode from "vscode";
import { DirectoryReader, discoverProjects, sortProjects } from "../projects";
import { projectOpenIn, projectRoots } from "./settings";
import { releaseKeys, takePendingKeys } from "./whichKey";

const RECENT_KEY = "orgflow.recentProjects";
const CACHE_KEY = "orgflow.knownProjects";
const PENDING_FILE = "pending-open.json";
const PENDING_MAX_AGE_MS = 30_000;
const RECENT_LIMIT = 100;

const reader: DirectoryReader = {
  async directories(path) {
    try {
      const entries = await vscode.workspace.fs.readDirectory(vscode.Uri.file(path));
      return entries
        .filter(([, type]) => (type & vscode.FileType.Directory) !== 0)
        .map(([name]) => name);
    } catch {
      return [];
    }
  },
  async isRepository(path) {
    try {
      await vscode.workspace.fs.stat(vscode.Uri.joinPath(vscode.Uri.file(path), ".git"));
      return true;
    } catch {
      return false;
    }
  },
};

function pendingUri(context: vscode.ExtensionContext): vscode.Uri {
  return vscode.Uri.joinPath(context.globalStorageUri, PENDING_FILE);
}

function isOpenHere(path: string): boolean {
  return (vscode.workspace.workspaceFolders ?? []).some(
    (folder) => folder.uri.fsPath === path,
  );
}

function display(path: string): string {
  const home = homedir();
  return path.startsWith(`${home}/`) ? `~${path.slice(home.length)}` : path;
}

function recentProjects(context: vscode.ExtensionContext): string[] {
  return context.globalState.get<string[]>(RECENT_KEY, []);
}

async function remember(context: vscode.ExtensionContext, path: string) {
  const recent = [path, ...recentProjects(context).filter((p) => p !== path)];
  await context.globalState.update(RECENT_KEY, recent.slice(0, RECENT_LIMIT));
}

async function findFile() {
  await vscode.commands.executeCommand("workbench.action.quickOpen");
}

/** Another window may have asked this one to open find-file once it's ready. */
export async function consumePendingOpen(context: vscode.ExtensionContext) {
  const uri = pendingUri(context);
  let pending: { target: string; requestedAt: number };
  try {
    const bytes = await vscode.workspace.fs.readFile(uri);
    pending = JSON.parse(Buffer.from(bytes).toString("utf8"));
  } catch {
    return;
  }
  const expired = Date.now() - pending.requestedAt > PENDING_MAX_AGE_MS;
  if (expired || isOpenHere(pending.target)) {
    await vscode.workspace.fs.delete(uri).then(undefined, () => undefined);
  }
  if (!expired && isOpenHere(pending.target)) {
    await findFile();
  }
}

async function openProject(context: vscode.ExtensionContext, path: string) {
  await remember(context, path);
  if (isOpenHere(path)) {
    await findFile();
    return;
  }
  await vscode.workspace.fs.createDirectory(context.globalStorageUri);
  await vscode.workspace.fs.writeFile(
    pendingUri(context),
    Buffer.from(JSON.stringify({ target: path, requestedAt: Date.now() })),
  );
  await vscode.commands.executeCommand("vscode.openFolder", vscode.Uri.file(path), {
    forceNewWindow: projectOpenIn() === "newWindow",
  });
}

export async function switchProject(context: vscode.ExtensionContext) {
  const picker = vscode.window.createQuickPick<
    vscode.QuickPickItem & { path: string }
  >();
  picker.title = "Switch to project";
  picker.placeholder = "Type to filter";
  picker.matchOnDescription = true;

  const show = (paths: string[]) => {
    const active = picker.activeItems[0]?.path;
    picker.items = sortProjects(paths, recentProjects(context)).map((path) => ({
      label: path.split("/").pop() ?? path,
      description: display(path),
      path,
    }));
    const keep = picker.items.find((item) => item.path === active);
    if (keep) {
      picker.activeItems = [keep];
    }
  };

  // Show what we knew last time immediately, then refresh once the scan finishes.
  show(context.globalState.get<string[]>(CACHE_KEY, []));
  picker.busy = true;
  picker.show();
  picker.value = takePendingKeys();

  const chosen = new Promise<string | undefined>((resolve) => {
    picker.onDidAccept(() => {
      resolve(picker.activeItems[0]?.path);
      picker.hide();
    });
    picker.onDidHide(() => {
      resolve(undefined);
      picker.dispose();
    });
  });

  void discoverProjects(projectRoots(), reader).then(async (found) => {
    await context.globalState.update(CACHE_KEY, found);
    picker.busy = false;
    show(found);
  });

  const path = await chosen;
  await releaseKeys();
  if (path) {
    await openProject(context, path);
  }
}

export function activateProjects(context: vscode.ExtensionContext) {
  const here = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (here) {
    void remember(context, here);
  }
  context.subscriptions.push(
    vscode.commands.registerCommand("orgflow.switchProject", () =>
      switchProject(context),
    ),
    vscode.window.onDidChangeWindowState((state) => {
      if (state.focused) {
        void consumePendingOpen(context);
      }
    }),
  );
  void consumePendingOpen(context);
}
