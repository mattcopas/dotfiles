// The agenda engine. The behaviour and the layout both follow org-agenda, and
// test/golden holds the real org output these views are compared with.
import {
  addMonths,
  Clock,
  DAY_LONG,
  fromAbs,
  isoWeek,
  MONTH_LONG,
  weekday,
} from "./date";
import { matches, parseMatch } from "./match";
import { OrgConfig, OrgDocument, OrgHeading, parseOrg } from "./parser";
import {
  findTimestamps,
  nextOccurrence,
  previousOccurrence,
  Timestamp,
  warningDays,
} from "./timestamp";

export { addMonths };

export type SkipRule =
  | { if: "todo" | "nottodo"; value: string | string[]; scope?: "entry" | "subtree" }
  | { if: "priority"; value: string; scope?: "entry" | "subtree" }
  | { if: "scheduled" | "deadline"; scope?: "entry" | "subtree" };

export interface AgendaBlock {
  type: "agenda" | "tags" | "tags-todo" | "alltodo";
  match?: string;
  header?: string;
  skip?: SkipRule[];
}

export interface AgendaView {
  key: string;
  description: string;
  blocks: AgendaBlock[];
}

export interface AgendaFile {
  path: string;
  /** Category when the file doesn't set one: the name without `.org`. */
  base: string;
  text: string;
}

export type ItemKind = "scheduled" | "deadline" | "timestamp" | "todo" | "tag";

export interface AgendaTarget {
  path: string;
  line: number;
  /** The heading line when rendered, used to detect that the file has moved on. */
  raw: string;
  kind: ItemKind;
}

export interface AgendaLine {
  text: string;
  target?: AgendaTarget;
}

export interface AgendaOptions {
  config: OrgConfig;
  clock: Clock;
  /** Window width. Tags right-align to this, and separators fill it. */
  width: number;
  weekOffset?: number;
  deadlineWarningDays?: number;
}

interface ParsedFile {
  path: string;
  doc: OrgDocument;
}

interface Item {
  file: ParsedFile;
  heading: OrgHeading;
  kind: ItemKind;
  leader: string;
  urgency: number;
  minutes: number | null;
  endMinutes: number | null;
}

function priorityValue(heading: OrgHeading, config: OrgConfig): number {
  const cookie = heading.priority ?? config.defaultPriority;
  if (cookie.length !== 1 || !/[A-Z]/.test(cookie)) {
    return 0;
  }
  return 1000 * ("C".charCodeAt(0) - cookie.charCodeAt(0));
}

/** org shows tags as `:inherited::local:`, with the seam between the two groups. */
function tagText(heading: OrgHeading): string {
  const { inheritedTags: inherited, localTags: local } = heading;
  if (!inherited.length && !local.length) {
    return "";
  }
  if (!inherited.length) {
    return `:${local.join(":")}:`;
  }
  return `:${inherited.join(":")}:${local.length ? `:${local.join(":")}:` : ":"}`;
}

function clockTime(minutes: number): string {
  const h = Math.floor(minutes / 60);
  return `${String(h).padStart(2, " ")}:${String(minutes % 60).padStart(2, "0")}`;
}

function formatLine(item: Item, options: AgendaOptions, withTime: boolean): AgendaLine {
  const category = `${item.heading.category}:`.padEnd(12, " ");
  let time = "";
  if (withTime && item.minutes !== null) {
    const span =
      item.endMinutes !== null
        ? `${clockTime(item.minutes)}-${clockTime(item.endMinutes).trim()}`
        : `${clockTime(item.minutes)}......`;
    time = `${span} `;
  }
  const base = `  ${category}${time}${item.leader}${item.heading.text}`;
  const tags = tagText(item.heading);
  const column = options.width - 1;
  const gap = Math.max(1, column - base.length - tags.length);
  return {
    text: tags ? `${base}${" ".repeat(gap)}${tags}` : base,
    target: {
      path: item.file.path,
      line: item.heading.line,
      raw: item.file.doc.lines[item.heading.line],
      kind: item.kind,
    },
  };
}

function ruleApplies(
  rule: SkipRule,
  heading: OrgHeading,
  options: AgendaOptions,
): boolean {
  const { config } = options;
  switch (rule.if) {
    case "todo":
    case "nottodo": {
      const words = wordsFor(rule.value, config);
      const hit = !!heading.keyword && words.has(heading.keyword);
      return rule.if === "todo" ? hit : !hit;
    }
    case "priority":
      return (heading.priority ?? config.defaultPriority) === rule.value;
    case "scheduled":
      return heading.scheduled !== null;
    case "deadline":
      return heading.deadline !== null;
  }
}

function wordsFor(value: string | string[], config: OrgConfig): Set<string> {
  if (Array.isArray(value)) {
    return new Set(value);
  }
  switch (value) {
    case "done":
      return config.doneWords;
    case "todo":
      return config.todoWords;
    case "any":
      return new Set(config.keywords);
    default:
      throw new Error(`Unknown TODO class "${value}"`);
  }
}

/** The heading index to continue from when a skip rule fires, or null to keep it. */
function skipTo(
  block: AgendaBlock,
  heading: OrgHeading,
  doc: OrgDocument,
  options: AgendaOptions,
): number | null {
  for (const rule of block.skip ?? []) {
    if (!ruleApplies(rule, heading, options)) {
      continue;
    }
    if (rule.scope !== "subtree") {
      return heading.index + 1;
    }
    let next = heading.index + 1;
    while (next < doc.headings.length && doc.headings[next].level > heading.level) {
      next++;
    }
    return next;
  }
  return null;
}

function sortByUrgency(items: Item[]): Item[] {
  return items
    .map((item, order) => ({ item, order }))
    .sort((a, b) => b.item.urgency - a.item.urgency || a.order - b.order)
    .map(({ item }) => item);
}

function tagsBlock(
  block: AgendaBlock,
  files: ParsedFile[],
  options: AgendaOptions,
): AgendaLine[] {
  const matcher = parseMatch(block.match ?? "", block.type === "tags-todo");
  const items: Item[] = [];
  for (const file of files) {
    const { headings } = file.doc;
    let i = 0;
    while (i < headings.length) {
      const heading = headings[i];
      if (!matches(matcher, heading, options.config, options.clock)) {
        i++;
        continue;
      }
      const skip = skipTo(block, heading, file.doc, options);
      if (skip !== null) {
        i = skip;
        continue;
      }
      const priority = priorityValue(heading, options.config);
      items.push({
        file,
        heading,
        kind: "tag",
        leader: "",
        urgency: priority,
        minutes: null,
        endMinutes: null,
      });
      // org-tags-match-list-sublevels is t: a match doesn't hide its subtree.
      i += 1;
    }
  }
  const header = block.header ?? `Headlines with TAGS match: ${block.match}`;
  return [
    { text: header },
    ...sortByUrgency(items).map((item) => formatLine(item, options, false)),
  ];
}

function allTodoBlock(
  block: AgendaBlock,
  files: ParsedFile[],
  options: AgendaOptions,
): AgendaLine[] {
  const items: Item[] = [];
  for (const file of files) {
    const { headings } = file.doc;
    let i = 0;
    while (i < headings.length) {
      const heading = headings[i];
      if (!heading.keyword || options.config.doneWords.has(heading.keyword)) {
        i++;
        continue;
      }
      const skip = skipTo(block, heading, file.doc, options);
      if (skip !== null) {
        i = skip;
        continue;
      }
      items.push({
        file,
        heading,
        kind: "todo",
        leader: "",
        urgency: priorityValue(heading, options.config) + 1,
        minutes: null,
        endMinutes: null,
      });
      i++;
    }
  }
  const header = block.header ?? "Global list of TODO items of type: ALL";
  return [
    { text: header },
    ...sortByUrgency(items).map((item) => formatLine(item, options, false)),
  ];
}

function deadlineItem(
  file: ParsedFile,
  heading: OrgHeading,
  ts: Timestamp,
  current: number,
  options: AgendaOptions,
): Item | null {
  const { today } = options.clock;
  const deadline = ts.abs;
  const repeat = current <= today ? deadline : nextOccurrence(ts, current);
  const diff = deadline - current;
  const isToday = current === today;
  if (current !== deadline && current !== repeat) {
    if (!isToday) {
      return null;
    }
    if (deadline > current && diff > warningDays(ts, options.deadlineWarningDays ?? 14)) {
      return null;
    }
  }
  const done = !!heading.keyword && options.config.doneWords.has(heading.keyword);
  if (done && deadline !== current) {
    return null;
  }
  let leader: string;
  if (current === deadline || current === repeat) {
    leader = "Deadline:   ";
  } else if (deadline > current) {
    leader = `In ${String(diff).padStart(3, " ")} d.:  `;
  } else {
    leader = `${String(-diff).padStart(2, " ")} d. ago:  `;
  }
  const reminder = current !== deadline && current !== repeat;
  return {
    file,
    heading,
    kind: "deadline",
    leader,
    urgency: priorityValue(heading, options.config) + (isToday ? -diff : 0),
    minutes: reminder ? null : ts.minutes,
    endMinutes: reminder ? null : ts.endMinutes,
  };
}

function scheduledItem(
  file: ParsedFile,
  heading: OrgHeading,
  ts: Timestamp,
  current: number,
  options: AgendaOptions,
): Item | null {
  const { today } = options.clock;
  const schedule = ts.abs;
  const repeat = current <= today ? schedule : nextOccurrence(ts, current);
  const diff = current - schedule;
  const delay = ts.warning ? warningDays(ts, 0) : 0;
  if (
    (delay > 0 && diff < delay) ||
    schedule > current ||
    (current !== schedule && current !== today && current !== repeat)
  ) {
    return null;
  }
  const done = !!heading.keyword && options.config.doneWords.has(heading.keyword);
  if (done && schedule !== current) {
    return null;
  }
  const isBase = current === schedule || current === repeat;
  const past = current === today && schedule < today && !isBase;
  const pastOrToday = current === today && schedule < today;
  const leader =
    past || pastOrToday
      ? `Sched.${String(diff).padStart(2, " ")}x:  `
      : "Scheduled:  ";
  return {
    file,
    heading,
    kind: "scheduled",
    leader,
    urgency: 99 + diff + priorityValue(heading, options.config),
    minutes: isBase ? ts.minutes : null,
    endMinutes: isBase ? ts.endMinutes : null,
  };
}

function plainStampItems(
  file: ParsedFile,
  heading: OrgHeading,
  current: number,
  options: AgendaOptions,
): Item[] {
  const { today } = options.clock;
  const items: Item[] = [];
  const { lines } = file.doc;
  for (let line = heading.line; line < heading.entryEnd; line++) {
    if (/^\s*(SCHEDULED|DEADLINE|CLOSED):/.test(lines[line])) {
      continue;
    }
    for (const ts of findTimestamps(lines[line])) {
      if (!ts.active || ts.inRange) {
        continue;
      }
      const past = previousOccurrence(ts, current > today ? today : current);
      const future = current <= today ? past : nextOccurrence(ts, current);
      if (current < ts.abs || (current !== past && current !== future)) {
        continue;
      }
      items.push({
        file,
        heading,
        kind: "timestamp",
        leader: "",
        urgency: priorityValue(heading, options.config),
        minutes: ts.minutes,
        endMinutes: ts.endMinutes,
      });
    }
  }
  return items;
}

const GRID_TIMES = [800, 1000, 1200, 1400, 1600, 1800, 2000].map(
  (hhmm) => Math.floor(hhmm / 100) * 60 + (hhmm % 100),
);
const NOW_LINE = "now - - - - - - - - - - - - - - - - - - - - - - - - -";
const GRID_LINE = "----------------";

function gridLine(minutes: number, text: string): AgendaLine {
  return { text: `  ${"".padEnd(12, " ")}${clockTime(minutes)}...... ${text}` };
}

function dayEntries(
  current: number,
  files: ParsedFile[],
  block: AgendaBlock,
  options: AgendaOptions,
): AgendaLine[] {
  const items: Item[] = [];
  for (const file of files) {
    const fileItems: { deadlines: Item[]; scheduled: Item[]; stamps: Item[] } = {
      deadlines: [],
      scheduled: [],
      stamps: [],
    };
    for (const heading of file.doc.headings) {
      if (block.skip?.length) {
        const skip = skipTo(block, heading, file.doc, options);
        if (skip !== null) {
          continue;
        }
      }
      if (heading.deadline?.active) {
        const item = deadlineItem(file, heading, heading.deadline, current, options);
        if (item) {
          fileItems.deadlines.push(item);
        }
      }
      if (heading.scheduled?.active) {
        const item = scheduledItem(file, heading, heading.scheduled, current, options);
        if (item) {
          fileItems.scheduled.push(item);
        }
      }
      fileItems.stamps.push(...plainStampItems(file, heading, current, options));
    }
    items.push(...fileItems.deadlines, ...fileItems.scheduled, ...fileItems.stamps);
  }

  const timed = items
    .filter((item) => item.minutes !== null)
    .map((item, order) => ({ item, order }))
    .sort(
      (a, b) =>
        (a.item.minutes as number) - (b.item.minutes as number) ||
        b.item.urgency - a.item.urgency ||
        a.order - b.order,
    )
    .map(({ item }) => item);
  const untimed = sortByUrgency(items.filter((item) => item.minutes === null));

  const timedLines: { minutes: number; rank: number; line: AgendaLine }[] =
    timed.map((item) => ({
      minutes: item.minutes as number,
      rank: 1,
      line: formatLine(item, options, true),
    }));

  // org only draws the time grid on today, and only when something has a time.
  if (current === options.clock.today && timed.length) {
    const taken = new Set(timed.map((item) => item.minutes));
    for (const minutes of GRID_TIMES) {
      if (!taken.has(minutes)) {
        timedLines.push({ minutes, rank: 0, line: gridLine(minutes, GRID_LINE) });
      }
    }
    timedLines.push({
      minutes: options.clock.minutes,
      rank: 2,
      line: gridLine(options.clock.minutes, NOW_LINE),
    });
  }
  timedLines.sort((a, b) => a.minutes - b.minutes || a.rank - b.rank);

  return [
    ...timedLines.map(({ line }) => line),
    ...untimed.map((item) => formatLine(item, options, false)),
  ];
}

function dayHeader(abs: number): string {
  const { y, m, d } = fromAbs(abs);
  const name = DAY_LONG[weekday(abs)].padEnd(10, " ");
  const base = `${name} ${String(d).padStart(2, " ")} ${MONTH_LONG[m - 1]} ${String(y).padStart(4, " ")}`;
  return weekday(abs) === 1 ? `${base} W${String(isoWeek(abs)).padStart(2, "0")}` : base;
}

function agendaBlock(
  block: AgendaBlock,
  files: ParsedFile[],
  options: AgendaOptions,
): AgendaLine[] {
  const { today } = options.clock;
  const monday = today - ((weekday(today) + 6) % 7) + (options.weekOffset ?? 0) * 7;
  const week = String(isoWeek(monday)).padStart(2, "0");
  const lines: AgendaLine[] = [{ text: block.header ?? `Week-agenda (W${week}):` }];
  for (let day = 0; day < 7; day++) {
    const current = monday + day;
    lines.push({ text: dayHeader(current) });
    lines.push(...dayEntries(current, files, block, options));
  }
  return lines;
}

export function renderView(
  view: AgendaView,
  input: AgendaFile[],
  options: AgendaOptions,
): AgendaLine[] {
  const files: ParsedFile[] = input.map((file) => ({
    path: file.path,
    doc: parseOrg(file.text, options.config, file.base),
  }));
  const separator = "=".repeat(options.width - 1);
  const lines: AgendaLine[] = [];
  view.blocks.forEach((block, index) => {
    if (index > 0) {
      lines.push({ text: "" }, { text: separator });
    }
    switch (block.type) {
      case "agenda":
        lines.push(...agendaBlock(block, files, options));
        break;
      case "alltodo":
        lines.push(...allTodoBlock(block, files, options));
        break;
      default:
        lines.push(...tagsBlock(block, files, options));
    }
  });
  return lines;
}
