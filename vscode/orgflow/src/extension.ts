import type * as vscode from "vscode";
import { activateAgenda } from "./features/agenda";
import { activateCapture } from "./features/capture";
import { activateDecorations } from "./features/decorations";
import { activateJournal } from "./features/journal";
import { activateLanguage } from "./features/language";
import { activateOrgCommands } from "./features/orgCommands";
import { activateProjects } from "./features/projects";
import { activateWhichKey } from "./features/whichKey";

export function activate(context: vscode.ExtensionContext) {
  activateWhichKey(context);
  activateLanguage(context);
  activateDecorations(context);
  activateAgenda(context);
  activateOrgCommands(context);
  activateCapture(context);
  activateJournal(context);
  activateProjects(context);
}

export function deactivate() {}
