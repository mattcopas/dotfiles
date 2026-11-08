// org-journal's monthly files: finding the right day, adding a day heading,
// carrying unfinished items over, and starting a timed entry.
import { Clock, formatDate, fromAbs, isoDate, orgDate, toAbs } from "./date";
import { matches, Matcher, parseMatch } from "./match";
import { OrgConfig, OrgDocument, parseOrg, splitLines } from "./parser";

export interface JournalConfig {
  fileFormat: string;
  dateFormat: string;
  carryover: string;
}

export function journalFileName(abs: number, config: JournalConfig): string {
  return formatDate(config.fileFormat, abs);
}

interface DayEntry {
  abs: number;
  line: number;
  subtreeEnd: number;
  headingIndex: number;
}

/** Days are found through the CREATED property, because that's what org-journal reads. */
function dayEntries(doc: OrgDocument): DayEntry[] {
  const days: DayEntry[] = [];
  for (const heading of doc.headings) {
    if (heading.level !== 1) {
      continue;
    }
    const created = heading.properties.get("CREATED");
    const match = created?.match(/^(\d{4})(\d{2})(\d{2})$/);
    if (match) {
      days.push({
        abs: toAbs(Number(match[1]), Number(match[2]), Number(match[3])),
        line: heading.line,
        subtreeEnd: heading.subtreeEnd,
        headingIndex: heading.index,
      });
    }
  }
  return days;
}

/** The latest day before `before` in a file, if there is one. */
export function latestDayBefore(
  text: string,
  before: number,
  config: OrgConfig,
): number | null {
  const days = dayEntries(parseOrg(text, config))
    .map((day) => day.abs)
    .filter((abs) => abs < before);
  return days.length ? Math.max(...days) : null;
}

/** Reads the first date a file can hold from its name, for example `Nov-2026.org`. */
export function fileNameToMonth(name: string, config: JournalConfig): number | null {
  const pattern = config.fileFormat
    .replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    .replace(/%Y/g, "(?<y>\\d{4})")
    .replace(/%b/g, "(?<b>[A-Za-z]{3})")
    .replace(/%m/g, "(?<m>\\d{2})");
  const match = name.match(new RegExp(`^${pattern}$`));
  if (!match?.groups) {
    return null;
  }
  const year = Number(match.groups.y);
  let month = match.groups.m ? Number(match.groups.m) : 1;
  if (match.groups.b) {
    const found = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].indexOf(
      match.groups.b.toLowerCase(),
    );
    if (found < 0) {
      return null;
    }
    month = found + 1;
  }
  return toAbs(year, month, 1);
}

interface PathStep {
  start: number;
  end: number;
  text: string[];
}

interface CarryResult {
  text: string[];
  remaining: string[];
}

/** Ports org-journal--carryover, including how it de-duplicates shared parents. */
function collectCarryover(
  lines: string[],
  doc: OrgDocument,
  day: DayEntry,
  matcher: Matcher,
  config: OrgConfig,
  clock: Clock,
): CarryResult | null {
  const paths: PathStep[][] = [];
  const headings = doc.headings.slice(day.headingIndex);
  let i = 0;
  while (i < headings.length && headings[i].line < day.subtreeEnd) {
    const heading = headings[i];
    if (!matches(matcher, heading, config, clock)) {
      i++;
      continue;
    }
    const path: PathStep[] = [];
    let parentIndex = heading.parent;
    while (parentIndex !== null && doc.headings[parentIndex].level >= 2) {
      const parent = doc.headings[parentIndex];
      path.unshift({
        start: parent.line,
        end: parent.entryEnd,
        text: lines.slice(parent.line, parent.entryEnd),
      });
      parentIndex = parent.parent;
    }
    path.push({
      start: heading.line,
      end: heading.subtreeEnd,
      text: lines.slice(heading.line, heading.subtreeEnd),
    });
    paths.push(path);
    while (i < headings.length && headings[i].line < heading.subtreeEnd) {
      i++;
    }
  }
  if (!paths.length) {
    return null;
  }

  const cleared: PathStep[] = [];
  const text: string[] = [];
  let previous: PathStep[] | null = null;
  for (const path of paths) {
    path.forEach((step, index) => {
      // cl-loop's `count` advances before the body, so org-journal really does
      // compare against the entry one past the matching depth.
      const counter = index + 1;
      const other = previous?.[counter];
      if (!previous || !other || step.start > other.start) {
        text.push(...step.text);
        cleared.push(step);
      }
    });
    previous = path;
  }

  const deleted = new Array<boolean>(lines.length).fill(false);
  const nextLiveHeading = (from: number) => {
    for (const heading of doc.headings) {
      if (heading.line >= from && !deleted[heading.line]) {
        return heading;
      }
    }
    return undefined;
  };
  for (const step of [...cleared].reverse()) {
    const last = step.end - 1;
    let owner = doc.headings[0];
    for (const heading of doc.headings) {
      if (heading.line <= last && !deleted[heading.line]) {
        owner = heading;
      }
    }
    const next = nextLiveHeading(step.end);
    const hasChild = !!next && owner.line < next.line && next.level > owner.level;
    if (!hasChild) {
      for (let at = step.start; at < step.end; at++) {
        deleted[at] = true;
      }
    }
  }
  return { text, remaining: lines.filter((_, at) => !deleted[at]) };
}

const CARRIED_STAMP = /<(\d{4}-\d{2}-\d{2}(?: [A-Za-z]+)?)>/g;

/** Plain date stamps in carried text move to today. Planning lines keep their dates. */
function refreshStamps(lines: string[], today: number): string[] {
  return lines.map((line) =>
    /\b(SCHEDULED|DEADLINE):/.test(line)
      ? line
      : line.replace(CARRIED_STAMP, () => `<${orgDate(today)}>`),
  );
}

function dayHeader(abs: number, config: JournalConfig): string[] {
  const { y, m, d } = fromAbs(abs);
  const created = `${y}${String(m).padStart(2, "0")}${String(d).padStart(2, "0")}`;
  return [
    `* ${formatDate(config.dateFormat, abs)}`,
    ":PROPERTIES:",
    `:CREATED:  ${created}`,
    ":END:",
  ];
}

function toLines(text: string): { lines: string[]; finalNewline: boolean } {
  const lines = splitLines(text);
  if (lines[lines.length - 1] === "") {
    lines.pop();
    return { lines, finalNewline: true };
  }
  return { lines, finalNewline: false };
}

export interface JournalPlan {
  /** New text for today's file. */
  current: string;
  /** New text for an older file that lost carried items, when it isn't today's. */
  previous: string | null;
  /** Line of the new entry in today's file. */
  line: number;
}

export interface JournalInput {
  clock: Clock;
  config: JournalConfig;
  orgConfig: OrgConfig;
  /** Today's file, empty when it doesn't exist yet. */
  currentText: string;
  /** The file holding the most recent earlier day, when that isn't today's file. */
  previousText?: string;
  /** Adds no new timed entry when false. */
  addEntry?: boolean;
}

export function planNewEntry(input: JournalInput): JournalPlan {
  const { clock, config, orgConfig } = input;
  const { today, minutes } = clock;
  const { lines: start } = toLines(input.currentText);
  let lines = start;
  let previousLines =
    input.previousText !== undefined ? toLines(input.previousText) : null;
  const matcher = parseMatch(config.carryover);

  const doc0 = parseOrg(lines.join("\n"), orgConfig);
  const hadToday = dayEntries(doc0).some((day) => day.abs === today);

  // Add today's heading if it's missing, in date order.
  if (!hadToday) {
    const later = dayEntries(doc0).find((day) => day.abs > today);
    const at = later ? later.line : lines.length;
    lines = [...lines.slice(0, at), ...dayHeader(today, config), ...lines.slice(at)];
  }

  // Carry items over from the most recent earlier day.
  const donor = (() => {
    const inCurrent = dayEntries(parseOrg(lines.join("\n"), orgConfig)).filter(
      (day) => day.abs < today,
    );
    if (inCurrent.length) {
      return "current" as const;
    }
    return previousLines ? ("previous" as const) : null;
  })();

  let carried: string[] = [];
  let newPrevious: string | null = null;
  if (donor && config.carryover.trim()) {
    const source = donor === "current" ? lines : (previousLines as { lines: string[] }).lines;
    const doc = parseOrg(source.join("\n"), orgConfig);
    const days = dayEntries(doc).filter((day) => day.abs < today);
    if (days.length) {
      const latest = days.reduce((a, b) => (b.abs > a.abs ? b : a));
      const result = collectCarryover(source, doc, latest, matcher, orgConfig, clock);
      if (result) {
        carried = refreshStamps(result.text, today);
        if (donor === "current") {
          lines = result.remaining;
        } else {
          const finalNl = (previousLines as { finalNewline: boolean }).finalNewline;
          newPrevious = result.remaining.join("\n") + (finalNl ? "\n" : "");
          previousLines = { lines: result.remaining, finalNewline: finalNl };
        }
      }
    }
  }

  // Add carried items and the new entry at the end of today's subtree.
  const doc = parseOrg(lines.join("\n"), orgConfig);
  const todayEntry = dayEntries(doc).find((day) => day.abs === today);
  if (!todayEntry) {
    throw new Error(`Journal entry for ${isoDate(today)} went missing`);
  }
  let at = todayEntry.subtreeEnd;
  while (at > todayEntry.line + 1 && lines[at - 1].trim() === "") {
    at--;
  }
  const added = [...carried];
  if (input.addEntry !== false) {
    added.push(`** ${formatDate("%H:%M", today, minutes)} `);
  }
  const result = [...lines.slice(0, at), ...added, ...lines.slice(at)];
  const entryLine = at + added.length - 1;
  return {
    current: `${result.join("\n")}\n`,
    previous: newPrevious,
    line: Math.max(entryLine, todayEntry.line),
  };
}
