// Org's tag and property match language, for example
// `+work+PRIORITY="A"`, `+SCHEDULED="<today>"` or `work-done|TODO="WAIT"`.
import { Clock } from "./date";
import { OrgConfig, OrgHeading } from "./parser";
import { parseDateInput, Timestamp } from "./timestamp";

type Op = "=" | "<>" | "<" | "<=" | ">" | ">=";

type Term =
  | { kind: "tag"; negate: boolean; tag: string }
  | { kind: "regex"; negate: boolean; regex: RegExp }
  | {
      kind: "prop";
      negate: boolean;
      name: string;
      op: Op;
      value: string;
      isRegex: boolean;
    };

export interface Matcher {
  groups: Term[][];
  todoOnly: boolean;
  /** `/TODO|WAIT` part, when present. */
  todoFilter: string[] | null;
}

const TERM =
  /^([+-]?)(?:([A-Za-z_][\w-]*)(<>|<=|>=|=|<|>)("(?:[^"\\]|\\.)*"|\{[^}]*\}|-?\d+(?:\.\d+)?)|\{([^}]*)\}|([\w@#%]+))/;

function splitTopLevel(text: string, separator: string): string[] {
  const parts: string[] = [];
  let current = "";
  let quote = false;
  let brace = 0;
  for (const char of text) {
    if (char === '"') {
      quote = !quote;
    } else if (!quote && char === "{") {
      brace++;
    } else if (!quote && char === "}") {
      brace--;
    }
    if (char === separator && !quote && brace === 0) {
      parts.push(current);
      current = "";
    } else {
      current += char;
    }
  }
  parts.push(current);
  return parts;
}

export function parseMatch(match: string, todoOnly = false): Matcher {
  const [tagPart, ...todoParts] = splitTopLevel(match, "/");
  let todoFilter: string[] | null = null;
  let onlyNotDone = todoOnly;
  const todoPart = todoParts.join("/");
  if (todoPart) {
    const clean = todoPart.replace(/^!/, "");
    if (todoPart.startsWith("!")) {
      onlyNotDone = true;
    }
    todoFilter = clean ? clean.split("|") : null;
  }
  const groups = splitTopLevel(tagPart, "|").map((group) => {
    const terms: Term[] = [];
    let rest = group.trim();
    while (rest.length) {
      if (rest.startsWith("&")) {
        rest = rest.slice(1);
        continue;
      }
      const found = rest.match(TERM);
      if (!found) {
        throw new Error(`Can't read match expression at "${rest}"`);
      }
      rest = rest.slice(found[0].length);
      const negate = found[1] === "-";
      if (found[2]) {
        const raw = found[4];
        const isRegex = raw.startsWith("{");
        const value = raw.startsWith('"') || isRegex ? raw.slice(1, -1) : raw;
        terms.push({
          kind: "prop",
          negate,
          name: found[2].toUpperCase(),
          op: found[3] as Op,
          value,
          isRegex,
        });
      } else if (found[5] !== undefined) {
        terms.push({ kind: "regex", negate, regex: new RegExp(found[5]) });
      } else {
        terms.push({ kind: "tag", negate, tag: found[6] });
      }
    }
    return terms;
  });
  return { groups, todoOnly: onlyNotDone, todoFilter };
}

function compare(a: number | string, b: number | string, op: Op): boolean {
  switch (op) {
    case "=":
      return a === b;
    case "<>":
      return a !== b;
    case "<":
      return a < b;
    case "<=":
      return a <= b;
    case ">":
      return a > b;
    case ">=":
      return a >= b;
  }
}

/**
 * Stamps compare as exact instants, like org. A stamp with a time of day is not
 * equal to `<today>`, which means midnight, so `SCHEDULED="<today>"` skips items
 * scheduled at a specific time. Surprising, but that's what the agenda does.
 */
function stampMinutes(ts: Timestamp): number {
  return ts.abs * 1440 + (ts.minutes ?? 0);
}

function specMinutes(value: string, clock: Clock): number | null {
  const inner = value.slice(1, -1).trim();
  if (inner === "now") {
    return clock.today * 1440 + clock.minutes;
  }
  const parsed = parseDateInput(inner, clock.today);
  return parsed ? parsed.abs * 1440 + (parsed.minutes ?? 0) : null;
}

function priorityOf(heading: OrgHeading, config: OrgConfig): string {
  return heading.priority ?? config.defaultPriority;
}

function evaluateProp(
  term: Extract<Term, { kind: "prop" }>,
  heading: OrgHeading,
  allTags: string[],
  config: OrgConfig,
  clock: Clock,
): boolean {
  const stamp =
    term.name === "SCHEDULED"
      ? heading.scheduled
      : term.name === "DEADLINE"
        ? heading.deadline
        : term.name === "CLOSED"
          ? heading.closed
          : undefined;
  if (stamp !== undefined) {
    if (!stamp) {
      return term.op === "<>";
    }
    const target = specMinutes(term.value, clock);
    if (target === null) {
      return false;
    }
    return compare(stampMinutes(stamp), target, term.op);
  }
  let actual: string;
  switch (term.name) {
    case "TODO":
      actual = heading.keyword ?? "";
      break;
    case "PRIORITY":
      actual = priorityOf(heading, config);
      break;
    case "LEVEL":
      return compare(heading.level, Number(term.value), term.op);
    case "CATEGORY":
      actual = heading.category;
      break;
    case "ITEM":
      actual = heading.text;
      break;
    case "TAGS":
      actual = allTags.length ? `:${allTags.join(":")}:` : "";
      break;
    default:
      actual = heading.properties.get(term.name) ?? "";
  }
  if (term.isRegex) {
    const hit = new RegExp(term.value).test(actual);
    return term.op === "<>" ? !hit : hit;
  }
  const number = Number(term.value);
  if (term.value !== "" && !Number.isNaN(number) && !Number.isNaN(Number(actual))) {
    return compare(Number(actual), number, term.op);
  }
  return compare(actual, term.value, term.op);
}

export function matches(
  matcher: Matcher,
  heading: OrgHeading,
  config: OrgConfig,
  clock: Clock,
): boolean {
  if (matcher.todoOnly) {
    if (!heading.keyword || config.doneWords.has(heading.keyword)) {
      return false;
    }
  }
  if (
    matcher.todoFilter &&
    !(heading.keyword && matcher.todoFilter.includes(heading.keyword))
  ) {
    return false;
  }
  const allTags = [...heading.inheritedTags, ...heading.localTags];
  return matcher.groups.some((group) =>
    group.every((term) => {
      let hit: boolean;
      if (term.kind === "tag") {
        hit = allTags.includes(term.tag);
      } else if (term.kind === "regex") {
        hit = term.regex.test(heading.text);
      } else {
        hit = evaluateProp(term, heading, allTags, config, clock);
      }
      return term.negate ? !hit : hit;
    }),
  );
}
