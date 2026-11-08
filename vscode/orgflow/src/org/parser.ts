import { findTimestamps, Timestamp } from "./timestamp";

export interface Sequence {
  todo: string[];
  done: string[];
}

export interface OrgConfig {
  sequences: Sequence[];
  /** Hotkey for fast selection, keyed by keyword. */
  keys: Map<string, string>;
  defaultPriority: string;
  /** All keywords, longest first, because keywords may contain spaces. */
  keywords: string[];
  doneWords: Set<string>;
  todoWords: Set<string>;
}

/** Reads org's own notation: `["TODO(t)", "IN PROGRESS(p)", "|", "DONE(d)"]`. */
export function makeConfig(sequences: string[][]): OrgConfig {
  const keys = new Map<string, string>();
  const parsed: Sequence[] = sequences.map((sequence) => {
    const bar = sequence.indexOf("|");
    const read = (items: string[]) =>
      items.map((item) => {
        const match = item.match(/^(.*?)(?:\(([^)/]*)[^)]*\))?$/);
        const name = match ? match[1] : item;
        if (match?.[2]) {
          keys.set(name, match[2]);
        }
        return name;
      });
    if (bar >= 0) {
      return {
        todo: read(sequence.slice(0, bar)),
        done: read(sequence.slice(bar + 1)),
      };
    }
    return {
      todo: read(sequence.slice(0, -1)),
      done: read(sequence.slice(-1)),
    };
  });
  const todoWords = new Set(parsed.flatMap((s) => s.todo));
  const doneWords = new Set(parsed.flatMap((s) => s.done));
  return {
    sequences: parsed,
    keys,
    defaultPriority: "B",
    keywords: [...todoWords, ...doneWords].sort((a, b) => b.length - a.length),
    doneWords,
    todoWords,
  };
}

export interface OrgHeading {
  index: number;
  line: number;
  level: number;
  keyword: string | null;
  priority: string | null;
  title: string;
  /** Heading text as written, without stars or tags. Agenda lines show this. */
  text: string;
  localTags: string[];
  inheritedTags: string[];
  scheduled: Timestamp | null;
  deadline: Timestamp | null;
  closed: Timestamp | null;
  properties: Map<string, string>;
  category: string;
  /** First line after this heading's own text: the next heading of any level. */
  entryEnd: number;
  /** First line after the whole subtree. */
  subtreeEnd: number;
  parent: number | null;
}

export interface OrgDocument {
  lines: string[];
  headings: OrgHeading[];
  fileTags: string[];
  category: string;
}

const HEADING = /^(\*+) (.*)$/;
const TAGS = /(?:^|[ \t]+):([\w@#%:]+):[ \t]*$/;

export interface ParsedLine {
  level: number;
  keyword: string | null;
  priority: string | null;
  title: string;
  text: string;
  tags: string[];
}

export function parseHeadingLine(
  line: string,
  config: OrgConfig,
): ParsedLine | null {
  const match = line.match(HEADING);
  if (!match) {
    return null;
  }
  let body = match[2];
  let tags: string[] = [];
  const tagMatch = body.match(TAGS);
  if (tagMatch && tagMatch.index !== undefined) {
    tags = tagMatch[1].split(":").filter(Boolean);
    body = body.slice(0, tagMatch.index);
  }
  const text = body.replace(/[ \t]+$/, "");
  let rest = text;
  let keyword: string | null = null;
  for (const candidate of config.keywords) {
    if (rest === candidate || rest.startsWith(`${candidate} `)) {
      keyword = candidate;
      rest = rest.slice(candidate.length).replace(/^ +/, "");
      break;
    }
  }
  let priority: string | null = null;
  const cookie = rest.match(/^\[#([A-Z0-9]+)\] */);
  if (cookie) {
    priority = cookie[1];
    rest = rest.slice(cookie[0].length);
  }
  return {
    level: match[1].length,
    keyword,
    priority,
    title: rest,
    text,
    tags,
  };
}

function readKeywordLines(lines: string[]) {
  const fileTags: string[] = [];
  let category: string | null = null;
  for (const line of lines) {
    if (HEADING.test(line)) {
      break;
    }
    const match = line.match(/^#\+([A-Za-z_]+):[ \t]*(.*?)[ \t]*$/);
    if (!match) {
      continue;
    }
    const key = match[1].toUpperCase();
    if (key === "FILETAGS") {
      fileTags.push(...match[2].split(":").filter(Boolean));
    } else if (key === "CATEGORY") {
      category = match[2];
    }
  }
  return { fileTags, category };
}

function readPlanning(line: string | undefined) {
  const planning: {
    scheduled: Timestamp | null;
    deadline: Timestamp | null;
    closed: Timestamp | null;
  } = { scheduled: null, deadline: null, closed: null };
  if (line === undefined || !/^\s*(SCHEDULED|DEADLINE|CLOSED):/.test(line)) {
    return planning;
  }
  for (const ts of findTimestamps(line)) {
    const label = line.slice(0, ts.column).match(/(SCHEDULED|DEADLINE|CLOSED):\s*$/);
    if (label?.[1] === "SCHEDULED") {
      planning.scheduled = ts;
    } else if (label?.[1] === "DEADLINE") {
      planning.deadline = ts;
    } else if (label?.[1] === "CLOSED") {
      planning.closed = ts;
    }
  }
  return planning;
}

function readProperties(lines: string[], from: number, end: number) {
  const properties = new Map<string, string>();
  let i = from;
  if (i < end && /^\s*(SCHEDULED|DEADLINE|CLOSED):/.test(lines[i])) {
    i++;
  }
  if (i >= end || !/^\s*:PROPERTIES:\s*$/.test(lines[i])) {
    return properties;
  }
  for (i++; i < end && !/^\s*:END:\s*$/.test(lines[i]); i++) {
    const match = lines[i].match(/^\s*:([^:\s]+):\s*(.*?)\s*$/);
    if (match) {
      properties.set(match[1].toUpperCase(), match[2]);
    }
  }
  return properties;
}

export function splitLines(text: string): string[] {
  return text.split(/\r?\n/);
}

export function parseOrg(
  text: string,
  config: OrgConfig,
  fileBase = "",
): OrgDocument {
  const lines = splitLines(text);
  const { fileTags, category } = readKeywordLines(lines);
  const fileCategory = category ?? fileBase;
  const headings: OrgHeading[] = [];
  const stack: OrgHeading[] = [];

  lines.forEach((line, lineNumber) => {
    const parsed = parseHeadingLine(line, config);
    if (!parsed) {
      return;
    }
    while (stack.length && stack[stack.length - 1].level >= parsed.level) {
      stack.pop();
    }
    const parent = stack.length ? stack[stack.length - 1] : null;
    const inherited = parent
      ? [...parent.inheritedTags, ...parent.localTags]
      : [...fileTags];
    const heading: OrgHeading = {
      index: headings.length,
      line: lineNumber,
      level: parsed.level,
      keyword: parsed.keyword,
      priority: parsed.priority,
      title: parsed.title,
      text: parsed.text,
      localTags: parsed.tags,
      inheritedTags: [...new Set(inherited)].filter(
        (tag) => !parsed.tags.includes(tag),
      ),
      scheduled: null,
      deadline: null,
      closed: null,
      properties: new Map(),
      category: parent ? parent.category : fileCategory,
      entryEnd: lines.length,
      subtreeEnd: lines.length,
      parent: parent ? parent.index : null,
    };
    headings.push(heading);
    stack.push(heading);
  });

  // Splitting on a final newline leaves an empty last element that isn't a real line.
  // It must not count as part of the last subtree, or moving that subtree moves it.
  const contentEnd = lines[lines.length - 1] === "" ? lines.length - 1 : lines.length;

  headings.forEach((heading, i) => {
    heading.entryEnd = i + 1 < headings.length ? headings[i + 1].line : contentEnd;
    let next = i + 1;
    while (next < headings.length && headings[next].level > heading.level) {
      next++;
    }
    heading.subtreeEnd = next < headings.length ? headings[next].line : contentEnd;
    Object.assign(heading, readPlanning(lines[heading.line + 1]));
    heading.properties = readProperties(lines, heading.line + 1, heading.entryEnd);
    const own = heading.properties.get("CATEGORY");
    if (own) {
      heading.category = own;
      for (let j = i + 1; j < headings.length && headings[j].level > heading.level; j++) {
        headings[j].category = own;
      }
    }
  });

  return { lines, headings, fileTags, category: fileCategory };
}

/** The heading whose entry contains `line`, if any. */
export function headingAt(
  doc: OrgDocument,
  line: number,
): OrgHeading | undefined {
  let found: OrgHeading | undefined;
  for (const heading of doc.headings) {
    if (heading.line > line) {
      break;
    }
    found = heading;
  }
  return found;
}
