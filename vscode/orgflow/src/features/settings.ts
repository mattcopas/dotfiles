import { homedir } from "node:os";
import { join } from "node:path";
import * as vscode from "vscode";
import { MenuNode } from "../keySequence";
import { AgendaView } from "../org/agenda";
import { JournalConfig } from "../org/journal";
import { makeConfig, OrgConfig } from "../org/parser";
import { ProjectRoot } from "../projects";

function section() {
  return vscode.workspace.getConfiguration("orgflow");
}

export function expandPath(path: string): string {
  if (path === "~") {
    return homedir();
  }
  return path.startsWith("~/") ? join(homedir(), path.slice(2)) : path;
}

export function orgConfig(): OrgConfig {
  return makeConfig(section().get<string[][]>("todoKeywords", []));
}

export function agendaFiles(): string[] {
  return section().get<string[]>("agenda.files", []).map(expandPath);
}

export function agendaViews(): AgendaView[] {
  return section().get<AgendaView[]>("agenda.views", []);
}

export function agendaWidth(): number {
  return section().get<number>("agenda.width", 100);
}

export function deadlineWarningDays(): number {
  return section().get<number>("agenda.deadlineWarningDays", 14);
}

export interface CaptureTemplate {
  key: string;
  description: string;
  file?: string;
  headline?: string;
  prepend?: boolean;
  schedule?: string;
}

export function captureTemplates(): CaptureTemplate[] {
  return section().get<CaptureTemplate[]>("capture.templates", []);
}

export function journalDirectory(): string {
  return expandPath(section().get<string>("journal.directory", "~/git/journal"));
}

export function journalConfig(): JournalConfig {
  return {
    fileFormat: section().get<string>("journal.fileFormat", "%b-%Y.org"),
    dateFormat: section().get<string>("journal.dateFormat", "%a %e %b %Y"),
    carryover: section().get<string>("journal.carryover", ""),
  };
}

export function startupFolded(): boolean {
  return section().get<boolean>("startupFolded", true);
}

export function hideMarkup(): boolean {
  return section().get<boolean>("hideMarkup", true);
}

export function projectRoots(): ProjectRoot[] {
  const roots = section().get<(string | { path: string; recursive?: boolean })[]>(
    "projects.roots",
    [],
  );
  return roots.map((root) =>
    typeof root === "string"
      ? { path: expandPath(root), recursive: false }
      : { path: expandPath(root.path), recursive: root.recursive ?? false },
  );
}

export function projectOpenIn(): "newWindow" | "currentWindow" {
  return section().get<"newWindow" | "currentWindow">("projects.openIn", "newWindow");
}

export function whichKeyMenu(): MenuNode {
  return {
    key: "",
    name: "SPC",
    children: section().get<MenuNode[]>("whichKey.menu", []),
  };
}
