// org-capture: pick a template with single keys, type a title, and the entry goes
// to its file and headline without leaving what you were doing.
import * as vscode from "vscode";
import { treeFromKeys } from "../keySequence";
import { clockFromDate } from "../org/date";
import { captureEntry, CaptureSpec } from "../org/edits";
import { formatStamp, parseDateInput } from "../org/timestamp";
import { agendaProvider } from "./agenda";
import { readText, writeText } from "./files";
import { captureTemplates, expandPath, orgConfig } from "./settings";
import { pickFromMenu, releaseKeys, takePendingKeys } from "./whichKey";

export async function capture(templateKey?: string, titleOverride?: string) {
  const templates = captureTemplates();
  let key = templateKey;
  if (typeof key !== "string") {
    const node = await pickFromMenu(
      treeFromKeys(templates, (template) =>
        template.file ? { command: template.key } : { children: [] },
      ),
      "Capture",
    );
    key = node?.command;
  }
  const typedEarly = takePendingKeys();
  await releaseKeys();
  const template = templates.find((t) => t.key === key);
  if (!template?.file || !template.headline) {
    return;
  }
  const title =
    titleOverride ??
    (await vscode.window.showInputBox({
      title: template.description,
      placeHolder: "TODO title",
      value: typedEarly,
      valueSelection: [typedEarly.length, typedEarly.length],
    }));
  if (!title) {
    return;
  }
  const path = expandPath(template.file);
  const today = clockFromDate(new Date()).today;
  let spec: CaptureSpec = {
    headline: template.headline,
    prepend: template.prepend ?? false,
    entry: `TODO ${title}`,
  };
  if (template.schedule) {
    const date = parseDateInput(template.schedule, today);
    if (!date) {
      vscode.window.showWarningMessage(`Template ${template.key}: can't read the date "${template.schedule}"`);
      return;
    }
    // The trailing space and indented line match what the org-capture template writes.
    spec = {
      ...spec,
      entry: `TODO ${title} `,
      extraLines: [` SCHEDULED: ${formatStamp(date.abs, date.minutes)}`],
    };
  }
  const before = (await readText(path)) ?? "";
  const result = captureEntry(before, spec, orgConfig());
  await writeText(path, result.text);
  agendaProvider.refreshAll();
  vscode.window.setStatusBarMessage(`Captured to ${template.file}`, 3000);
}

export function activateCapture(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand("orgflow.capture", capture),
  );
}
