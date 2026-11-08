// org-journal-new-entry: open this month's file, carry unfinished items over from
// the most recent earlier day, and start a timed entry.
import { join } from "node:path";
import * as vscode from "vscode";
import { Clock, clockFromDate } from "../org/date";
import { fileNameToMonth, journalFileName, latestDayBefore, planNewEntry } from "../org/journal";
import { readText, showFresh, writeText } from "./files";
import { markOpened, revealLine } from "./language";
import { journalConfig, journalDirectory, orgConfig } from "./settings";

/** The newest journal file other than today's that has a day before today. */
async function previousFile(
  directory: string,
  currentName: string,
  today: number,
): Promise<{ path: string; text: string } | undefined> {
  const config = journalConfig();
  let names: [string, vscode.FileType][];
  try {
    names = await vscode.workspace.fs.readDirectory(vscode.Uri.file(directory));
  } catch {
    return undefined;
  }
  const dated = names
    .map(([name]) => ({ name, month: fileNameToMonth(name, config) }))
    .filter((file) => file.month !== null && file.name !== currentName)
    .sort((a, b) => (b.month as number) - (a.month as number));
  for (const { name, month } of dated) {
    if ((month as number) > today) {
      continue;
    }
    const path = join(directory, name);
    const text = await readText(path);
    if (text !== null && latestDayBefore(text, today, orgConfig()) !== null) {
      return { path, text };
    }
  }
  return undefined;
}

export async function newJournalEntry(clock: Clock = clockFromDate(new Date())) {
  const directory = journalDirectory();
  const config = journalConfig();
  const name = journalFileName(clock.today, config);
  const path = join(directory, name);
  const currentText = (await readText(path)) ?? "";
  const hasEarlierHere = latestDayBefore(currentText, clock.today, orgConfig()) !== null;
  const donor = hasEarlierHere ? undefined : await previousFile(directory, name, clock.today);

  const plan = planNewEntry({
    clock,
    config,
    orgConfig: orgConfig(),
    currentText,
    previousText: donor?.text,
  });

  await writeText(path, plan.current);
  if (donor && plan.previous !== null) {
    await writeText(donor.path, plan.previous);
  }

  markOpened(vscode.Uri.file(path));
  const editor = await showFresh(path);
  await revealLine(editor, plan.line, editor.document.lineAt(plan.line).text.length);
}

export function activateJournal(context: vscode.ExtensionContext) {
  context.subscriptions.push(
    vscode.commands.registerCommand("orgflow.journal.newEntry", () => newJournalEntry()),
  );
}
