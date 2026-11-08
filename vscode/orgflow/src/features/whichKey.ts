// A which-key style menu. It acts on single keypresses with no Enter needed, and
// the same picker drives the leader menu, capture templates and TODO states.
import * as vscode from "vscode";
import { filterMenu, MenuNode, walk } from "../keySequence";
import { whichKeyMenu } from "./settings";

// Between SPC and the picker existing there's a round trip to the extension host, and
// keys typed in that gap would reach Vim, where p pastes. Extensions can't set a context
// key synchronously, but the renderer can move focus synchronously. So SPC first focuses
// the status bar, where a letter can't reach the editor, and statusBarFocused routes it
// to orgflow.menuKey. The keys wait here until a picker is ready to take them, and focus
// always goes back to the editor when the menu is done.
const ESCAPE = "\u001b";

let pending: string[] = [];
let inputHandler: ((text: string) => void) | undefined;
let armed = false;

export function takePendingKeys(): string {
  const text = pending.filter((char) => char !== ESCAPE).join("");
  pending = [];
  return text;
}

/** Hands the keyboard back to the editor. Does nothing unless SPC moved focus away. */
export async function releaseKeys(): Promise<void> {
  if (armed) {
    armed = false;
    await vscode.commands.executeCommand("workbench.action.focusActiveEditorGroup");
  }
}

function menuKey(char: string) {
  if (inputHandler) {
    inputHandler(char);
  } else if (armed) {
    pending.push(char);
  } else {
    // Focus reached the status bar some other way, so don't trap the keyboard there.
    void vscode.commands.executeCommand("workbench.action.focusActiveEditorGroup");
  }
}

function keyLabel(key: string): string {
  return key === " " ? "SPC" : key;
}

/** Shows a menu tree and resolves with the chosen leaf, or undefined if cancelled. */
export function pickFromMenu(
  root: MenuNode,
  title: string,
): Promise<MenuNode | undefined> {
  return new Promise((resolve) => {
    const picker = vscode.window.createQuickPick<
      vscode.QuickPickItem & { node: MenuNode }
    >();
    let current = root;
    let path = title;
    let settled = false;

    const render = () => {
      picker.title = path;
      picker.placeholder = "Press a key";
      picker.items = (current.children ?? []).map((child) => ({
        label: keyLabel(child.key),
        description: child.name,
        node: child,
      }));
    };

    const finish = (node: MenuNode | undefined) => {
      if (settled) {
        return;
      }
      settled = true;
      inputHandler = undefined;
      picker.hide();
      resolve(node);
    };

    const descend = (node: MenuNode) => {
      current = node;
      path = `${path} ${keyLabel(node.key)}`;
      picker.value = "";
      render();
    };

    const handleKeys = (value: string) => {
      if (settled) {
        return;
      }
      if (value.includes(ESCAPE)) {
        finish(undefined);
        return;
      }
      const result = walk(current, value);
      if (result.kind === "leaf") {
        finish(result.node);
      } else if (result.kind === "branch") {
        descend(result.node);
      } else {
        vscode.window.setStatusBarMessage(
          `${path} ${keyLabel(result.badKey)} is undefined`,
          3000,
        );
        finish(undefined);
      }
    };

    picker.onDidChangeValue((value) => {
      if (value) {
        handleKeys(value);
      }
    });
    picker.onDidAccept(() => {
      const node = picker.activeItems[0]?.node;
      if (!node) {
        return;
      }
      if (node.children) {
        descend(node);
      } else {
        finish(node);
      }
    });
    picker.onDidHide(() => {
      finish(undefined);
      picker.dispose();
    });

    render();
    picker.show();
    inputHandler = handleKeys;
    // Everything typed before this point goes in now, one key at a time and in order.
    const early = pending;
    pending = [];
    for (const char of early) {
      handleKeys(char);
    }
  });
}

export async function runNode(node: MenuNode): Promise<void> {
  if (!node.command) {
    return;
  }
  try {
    if (node.args !== undefined) {
      await vscode.commands.executeCommand(node.command, node.args);
    } else {
      await vscode.commands.executeCommand(node.command);
    }
  } catch (error) {
    vscode.window.showWarningMessage(
      `${node.name}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }
}

/** Commands that open a picker of their own, and release the keyboard when they finish. */
const OPENS_PICKER = new Set([
  "orgflow.capture",
  "orgflow.agenda",
  "orgflow.switchProject",
]);

export async function openWhichKey(mode?: unknown): Promise<void> {
  armed = mode === "armed";
  const language = vscode.window.activeTextEditor?.document.languageId;
  const node = await pickFromMenu(filterMenu(whichKeyMenu(), language), "SPC");
  if (!node) {
    pending = [];
    await releaseKeys();
    return;
  }
  const opensPicker =
    (node.command !== undefined && OPENS_PICKER.has(node.command)) ||
    (node.command === "orgflow.org.setTodo" && node.args === undefined);
  if (opensPicker) {
    await runNode(node);
    pending = [];
    await releaseKeys();
    return;
  }
  // Return to the editor first, so the command acts there and whatever it opens
  // restores focus to the editor when it closes.
  pending = [];
  await releaseKeys();
  await runNode(node);
}

export function activateWhichKey(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand("orgflow.whichKey", openWhichKey),
    vscode.commands.registerCommand("orgflow.menuKey", menuKey),
  );
}
