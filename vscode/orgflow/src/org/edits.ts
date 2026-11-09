// Every edit is a pure function from old text to new text. minimalEdit then
// reduces that to the smallest changed span, so the editor only ever touches
// what really changed and anything the parser doesn't understand survives.
import { Clock } from "./date";
import { headingAt, OrgConfig, OrgHeading, parseHeadingLine, parseOrg } from "./parser";
import {
  findTimestamps,
  formatStamp,
  repeatedDate,
  Timestamp,
  withDate,
} from "./timestamp";

export interface TextChange {
  start: number;
  end: number;
  text: string;
}

export function minimalEdit(before: string, after: string): TextChange | null {
  if (before === after) {
    return null;
  }
  let start = 0;
  const limit = Math.min(before.length, after.length);
  while (start < limit && before[start] === after[start]) {
    start++;
  }
  let endBefore = before.length;
  let endAfter = after.length;
  while (
    endBefore > start &&
    endAfter > start &&
    before[endBefore - 1] === after[endAfter - 1]
  ) {
    endBefore--;
    endAfter--;
  }
  return { start, end: endBefore, text: after.slice(start, endAfter) };
}

function headingOrThrow(text: string, line: number, config: OrgConfig) {
  const doc = parseOrg(text, config);
  const heading = doc.headings.find((h) => h.line === line);
  if (!heading) {
    throw new Error(`Line ${line + 1} is not a heading`);
  }
  return { doc, heading };
}

function replaceKeyword(line: string, keyword: string | null, config: OrgConfig): string {
  const parsed = parseHeadingLine(line, config);
  if (!parsed) {
    return line;
  }
  const stars = "*".repeat(parsed.level);
  let rest = line.slice(stars.length + 1);
  if (parsed.keyword) {
    rest = rest.slice(parsed.keyword.length).replace(/^ /, "");
  }
  return `${stars} ${keyword ? `${keyword}${rest ? " " : ""}` : ""}${rest}`;
}

function sequenceHead(keyword: string | null, config: OrgConfig): string | null {
  if (!keyword) {
    return null;
  }
  const sequence = config.sequences.find(
    (s) => s.todo.includes(keyword) || s.done.includes(keyword),
  );
  return sequence?.todo[0] ?? sequence?.done[0] ?? null;
}

const PLANNING_LINE = /^\s*(SCHEDULED|DEADLINE|CLOSED):/;

function removeScheduledFrom(line: string): string {
  return line
    .replace(/SCHEDULED:\s*(<[^>]*>|\[[^\]]*\])\s*/, "")
    .replace(/\s+$/, "");
}

/**
 * Sets a heading's keyword. Completing a repeating entry moves its dates forward
 * and returns it to the start of its keyword sequence, as org does, with no
 * logging because the config sets org-log-repeat to nil.
 */
export function setTodo(
  text: string,
  line: number,
  keyword: string | null,
  config: OrgConfig,
  clock: Clock,
): string {
  const { doc, heading } = headingOrThrow(text, line, config);
  const lines = [...doc.lines];
  const previous = heading.keyword;
  const completing =
    keyword !== null &&
    config.doneWords.has(keyword) &&
    !(previous && config.doneWords.has(previous));

  const repeats = completing
    ? entryRepeaters(lines, heading)
    : [];
  if (!repeats.length) {
    lines[line] = replaceKeyword(lines[line], keyword, config);
    return lines.join("\n");
  }

  lines[line] = replaceKeyword(lines[line], sequenceHead(previous, config), config);
  for (const { line: at, stamp } of [...repeats].reverse()) {
    const next = withDate(stamp.raw, repeatedDate(stamp, clock));
    lines[at] =
      lines[at].slice(0, stamp.column) +
      next +
      lines[at].slice(stamp.column + stamp.raw.length);
  }
  // A non-repeating SCHEDULED beside a repeater would be stale, so org drops it.
  if (heading.scheduled && !heading.scheduled.repeater) {
    const planning = line + 1;
    const cleaned = removeScheduledFrom(lines[planning]);
    if (PLANNING_LINE.test(cleaned)) {
      lines[planning] = cleaned;
    } else {
      lines.splice(planning, 1);
    }
  }
  return lines.join("\n");
}

function entryRepeaters(lines: string[], heading: OrgHeading) {
  const found: { line: number; stamp: Timestamp }[] = [];
  for (let at = heading.line; at < heading.entryEnd; at++) {
    for (const stamp of findTimestamps(lines[at])) {
      if (stamp.active && stamp.repeater && stamp.repeater.n > 0) {
        found.push({ line: at, stamp });
      }
    }
  }
  return found;
}

/** Sets SCHEDULED or DEADLINE, keeping any repeater and the planning order. */
export function setPlanning(
  text: string,
  line: number,
  label: "SCHEDULED" | "DEADLINE",
  abs: number,
  minutes: number | null,
  config: OrgConfig,
): string {
  const { doc, heading } = headingOrThrow(text, line, config);
  const lines = [...doc.lines];
  const old = label === "SCHEDULED" ? heading.scheduled : heading.deadline;
  let stamp = formatStamp(abs, minutes);
  const tail = old?.raw.match(/((?:\s+(?:\.\+|\+\+|\+|--?)\d+[hdwmy](?:\/\d+[hdwmy])?)+)\s*>$/);
  if (tail) {
    stamp = `${stamp.slice(0, -1)}${tail[1]}>`;
  }
  const entry = `${label}: ${stamp}`;
  const planning = line + 1;
  if (planning < lines.length && PLANNING_LINE.test(lines[planning])) {
    const current = lines[planning];
    const pattern = new RegExp(`${label}:\\s*(?:<[^>]*>|\\[[^\\]]*\\])`);
    if (pattern.test(current)) {
      lines[planning] = current.replace(pattern, entry);
    } else if (label === "SCHEDULED") {
      lines[planning] = current.replace(/^(\s*)/, `$1${entry} `);
    } else {
      lines[planning] = `${current.replace(/\s+$/, "")} ${entry}`;
    }
  } else {
    lines.splice(planning, 0, entry);
  }
  return lines.join("\n");
}

/** Moves an existing planning stamp by a number of days. Null when there is none. */
export function shiftPlanning(
  text: string,
  line: number,
  label: "SCHEDULED" | "DEADLINE",
  days: number,
  config: OrgConfig,
): string | null {
  const { doc, heading } = headingOrThrow(text, line, config);
  const stamp = label === "SCHEDULED" ? heading.scheduled : heading.deadline;
  if (!stamp) {
    return null;
  }
  const lines = [...doc.lines];
  const at = line + 1;
  lines[at] =
    lines[at].slice(0, stamp.column) +
    withDate(stamp.raw, stamp.abs + days) +
    lines[at].slice(stamp.column + stamp.raw.length);
  return lines.join("\n");
}

/** Steps a priority cookie. No cookie goes to the default, and past the end removes it. */
export function changePriority(
  text: string,
  line: number,
  direction: "up" | "down",
  config: OrgConfig,
): string {
  const { doc } = headingOrThrow(text, line, config);
  const lines = [...doc.lines];
  const parsed = parseHeadingLine(lines[line], config);
  if (!parsed) {
    return text;
  }
  const order = ["A", "B", "C"];
  let next: string | null;
  if (!parsed.priority) {
    next = direction === "up" ? config.defaultPriority : config.defaultPriority;
  } else {
    const at = order.indexOf(parsed.priority) + (direction === "up" ? -1 : 1);
    next = at >= 0 && at < order.length ? order[at] : null;
  }
  const stars = "*".repeat(parsed.level);
  let rest = lines[line].slice(stars.length + 1);
  let prefix = "";
  if (parsed.keyword) {
    prefix = `${parsed.keyword} `;
    rest = rest.slice(parsed.keyword.length).replace(/^ /, "");
  }
  rest = rest.replace(/^\[#[A-Z0-9]+\] */, "");
  lines[line] = `${stars} ${prefix}${next ? `[#${next}] ` : ""}${rest}`;
  return lines.join("\n");
}

export function setTags(
  text: string,
  line: number,
  tags: string[],
  config: OrgConfig,
): string {
  const { doc } = headingOrThrow(text, line, config);
  const lines = [...doc.lines];
  const stripped = lines[line].replace(/[ \t]+:[\w@#%:]+:[ \t]*$/, "").replace(/[ \t]+$/, "");
  lines[line] = tags.length ? `${stripped} :${tags.join(":")}:` : stripped;
  return lines.join("\n");
}

function shiftStars(line: string, delta: number): string {
  const stars = line.match(/^\*+/)?.[0] ?? "";
  return `${"*".repeat(stars.length + delta)}${line.slice(stars.length)}`;
}

/** org-metaleft and org-metaright: changes this heading only, not its children. */
export function shiftHeading(
  text: string,
  line: number,
  delta: 1 | -1,
  config: OrgConfig,
): string {
  const { doc, heading } = headingOrThrow(text, line, config);
  if (heading.level + delta < 1) {
    throw new Error("Cannot promote to level 0");
  }
  const lines = [...doc.lines];
  lines[line] = shiftStars(lines[line], delta);
  return lines.join("\n");
}

/**
 * Shifts every heading in a range of lines, leaving other lines alone. A level 1 heading
 * can't be promoted, so it stays as it is.
 */
export function shiftHeadings(
  text: string,
  first: number,
  last: number,
  delta: 1 | -1,
  config: OrgConfig,
): string {
  const lines = text.split("\n");
  for (let line = first; line <= last && line < lines.length; line++) {
    const parsed = parseHeadingLine(lines[line], config);
    if (parsed && parsed.level + delta >= 1) {
      lines[line] = shiftStars(lines[line], delta);
    }
  }
  return lines.join("\n");
}

/** org-shiftmetaleft and org-shiftmetaright: changes the whole subtree. */
export function shiftSubtree(
  text: string,
  line: number,
  delta: 1 | -1,
  config: OrgConfig,
): string {
  const { doc, heading } = headingOrThrow(text, line, config);
  if (heading.level + delta < 1) {
    throw new Error("Cannot promote to level 0");
  }
  const lines = [...doc.lines];
  for (const other of doc.headings) {
    if (other.line >= heading.line && other.line < heading.subtreeEnd) {
      lines[other.line] = shiftStars(lines[other.line], delta);
    }
  }
  return lines.join("\n");
}

/** Swaps a subtree with its neighbouring sibling. Returns where it landed. */
export function moveSubtree(
  text: string,
  line: number,
  direction: "up" | "down",
  config: OrgConfig,
): { text: string; line: number } {
  const { doc, heading } = headingOrThrow(text, line, config);
  const siblings = doc.headings.filter((h) => h.parent === heading.parent);
  const at = siblings.indexOf(heading) + (direction === "up" ? -1 : 1);
  const other = siblings[at];
  if (!other || other.level !== heading.level) {
    throw new Error(
      direction === "up"
        ? "Cannot move past superior level or buffer limit"
        : "Cannot move past superior level or buffer limit",
    );
  }
  const first = direction === "up" ? other : heading;
  const second = direction === "up" ? heading : other;
  const { lines } = doc;
  const firstBlock = lines.slice(first.line, first.subtreeEnd);
  const secondBlock = lines.slice(second.line, second.subtreeEnd);
  // The last line of a file with no final newline has to swap its missing newline too.
  const result = [
    ...lines.slice(0, first.line),
    ...secondBlock,
    ...firstBlock,
    ...lines.slice(second.subtreeEnd),
  ];
  return {
    text: result.join("\n"),
    line: direction === "up" ? first.line : first.line + secondBlock.length,
  };
}

export interface CaptureSpec {
  headline: string;
  prepend: boolean;
  /** Entry text below the stars, for example `TODO Buy milk`. */
  entry: string;
  /** Extra lines for the entry, for example a scheduled line. */
  extraLines?: string[];
}

/** Places a captured entry under its headline, creating the headline if needed. */
export function captureEntry(
  text: string,
  spec: CaptureSpec,
  config: OrgConfig,
): { text: string; line: number } {
  const doc = parseOrg(text, config);
  const lines = [...doc.lines];
  const target = doc.headings.find(
    (h) => h.level === 1 && h.title === spec.headline,
  );
  const body = (level: number) => [
    `${"*".repeat(level)} ${spec.entry}`,
    ...(spec.extraLines ?? []),
  ];

  if (!target) {
    const hasFinalNewline = lines[lines.length - 1] === "";
    const base = hasFinalNewline ? lines.slice(0, -1) : lines;
    const prefix = base.length === 1 && base[0] === "" ? [] : base;
    const added = [`* ${spec.headline}`, ...body(2)];
    return {
      text: [...prefix, ...added, ""].join("\n"),
      line: prefix.length + 1,
    };
  }

  let at: number;
  if (spec.prepend) {
    const child = doc.headings.find(
      (h) => h.line > target.line && h.line < target.subtreeEnd,
    );
    at = child ? child.line : target.subtreeEnd;
  } else {
    at = target.subtreeEnd;
  }
  // Keep blank lines that separate this subtree from the next heading.
  if (at === target.subtreeEnd) {
    while (at > target.line + 1 && lines[at - 1].trim() === "") {
      at--;
    }
  }
  const noFinalNewline = at === lines.length && lines[at - 1] !== "";
  const entry = body(target.level + 1);
  if (noFinalNewline) {
    lines.push(...entry);
    lines.push("");
  } else {
    lines.splice(at, 0, ...entry);
  }
  return { text: lines.join("\n"), line: at };
}

export { headingAt };
