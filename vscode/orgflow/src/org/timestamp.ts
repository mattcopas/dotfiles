import {
  addMonths,
  Clock,
  DAY_SHORT,
  fromAbs,
  isoDate,
  orgDate,
  toAbs,
  weekday,
} from "./date";

export type RepeaterType = "+" | "++" | ".+";
export type Unit = "h" | "d" | "w" | "m" | "y";

export interface Repeater {
  type: RepeaterType;
  n: number;
  unit: Unit;
}

export interface Timestamp {
  active: boolean;
  abs: number;
  /** Minutes since midnight, when the stamp has a time. */
  minutes: number | null;
  endMinutes: number | null;
  repeater: Repeater | null;
  warning: { n: number; unit: Unit; once: boolean } | null;
  raw: string;
  /** Column of the opening bracket in its line. */
  column: number;
}

const STAMP =
  /([<[])(\d{4})-(\d{2})-(\d{2})(?: +[^\s\d>\]+.-]+)?(?: +(\d{1,2}):(\d{2})(?:-(\d{1,2}):(\d{2}))?)?((?: +[^>\]\n]*?)?) *([>\]])/g;

function parseOptions(options: string) {
  const repeat = options.match(/(?:^|\s)(\.\+|\+\+|\+)(\d+)([hdwmy])/);
  const warn = options.match(/(?:^|\s)(--?)(\d+)([hdwmy])/);
  return {
    repeater: repeat
      ? {
          type: repeat[1] as RepeaterType,
          n: Number(repeat[2]),
          unit: repeat[3] as Unit,
        }
      : null,
    warning: warn
      ? { once: warn[1] === "--", n: Number(warn[2]), unit: warn[3] as Unit }
      : null,
  };
}

/** Every timestamp in a line, with date ranges reported by their own flag. */
export function findTimestamps(
  line: string,
): (Timestamp & { inRange: boolean })[] {
  const found: (Timestamp & { inRange: boolean })[] = [];
  STAMP.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = STAMP.exec(line))) {
    const open = match[1];
    const close = match[10];
    if ((open === "<") !== (close === ">")) {
      continue;
    }
    const { repeater, warning } = parseOptions(match[9] ?? "");
    const end = match.index + match[0].length;
    found.push({
      active: open === "<",
      abs: toAbs(Number(match[2]), Number(match[3]), Number(match[4])),
      minutes:
        match[5] === undefined
          ? null
          : Number(match[5]) * 60 + Number(match[6]),
      endMinutes:
        match[7] === undefined
          ? null
          : Number(match[7]) * 60 + Number(match[8]),
      repeater,
      warning,
      raw: match[0],
      column: match.index,
      inRange:
        line.slice(end, end + 2) === "--" ||
        line.slice(Math.max(0, match.index - 2), match.index) === "--",
    });
  }
  return found;
}

export function parseTimestamp(text: string): Timestamp | null {
  return findTimestamps(text)[0] ?? null;
}

function stepDays(repeater: Repeater): number {
  switch (repeater.unit) {
    case "h":
      return Math.max(1, Math.floor(repeater.n / 24));
    case "w":
      return repeater.n * 7;
    default:
      return repeater.n;
  }
}

function monthStep(repeater: Repeater): number | null {
  if (repeater.unit === "m") {
    return repeater.n;
  }
  return repeater.unit === "y" ? repeater.n * 12 : null;
}

/** The first occurrence of a stamp on or after `current`, never before its base. */
export function nextOccurrence(ts: Timestamp, current: number): number {
  if (!ts.repeater || current <= ts.abs || ts.repeater.n === 0) {
    return ts.abs;
  }
  const months = monthStep(ts.repeater);
  if (months !== null) {
    let k = 0;
    while (addMonths(ts.abs, k * months) < current) {
      k++;
    }
    return addMonths(ts.abs, k * months);
  }
  const step = stepDays(ts.repeater);
  return ts.abs + Math.ceil((current - ts.abs) / step) * step;
}

/** The last occurrence of a stamp on or before `current`. */
export function previousOccurrence(ts: Timestamp, current: number): number {
  if (!ts.repeater || current <= ts.abs || ts.repeater.n === 0) {
    return ts.abs;
  }
  const months = monthStep(ts.repeater);
  if (months !== null) {
    let k = 0;
    while (addMonths(ts.abs, (k + 1) * months) <= current) {
      k++;
    }
    return addMonths(ts.abs, k * months);
  }
  const step = stepDays(ts.repeater);
  return ts.abs + Math.floor((current - ts.abs) / step) * step;
}

/** Days of warning in a `-3d` cookie, or the fallback when there is none. */
export function warningDays(ts: Timestamp, fallback: number): number {
  if (!ts.warning) {
    return fallback;
  }
  const scale = { h: 1 / 24, d: 1, w: 7, m: 30.4, y: 365.25 }[ts.warning.unit];
  return Math.floor(ts.warning.n * scale);
}

/** Replaces only the date in a raw stamp, keeping time, repeater and warning. */
export function withDate(raw: string, abs: number): string {
  return raw.replace(
    /\d{4}-\d{2}-\d{2}(?: +[^\s\d>\]+.-]+)?/,
    orgDate(abs),
  );
}

function shift(abs: number, repeater: Repeater): number {
  const months = monthStep(repeater);
  if (months !== null) {
    return addMonths(abs, months);
  }
  return abs + stepDays(repeater);
}

/** Where a repeating stamp lands when its entry is marked done. */
export function repeatedDate(ts: Timestamp, clock: Clock): number {
  const repeater = ts.repeater;
  if (!repeater) {
    return ts.abs;
  }
  switch (repeater.type) {
    case ".+":
      return shift(clock.today, repeater);
    case "++": {
      let abs = ts.abs;
      do {
        abs = shift(abs, repeater);
      } while (abs <= clock.today);
      return abs;
    }
    default:
      return shift(ts.abs, repeater);
  }
}

/**
 * Reads a date as typed at a schedule prompt: `+1d`, `-2w`, `.`, `today`,
 * `tomorrow`, `fri`, `2026-11-12`, `11-12` or `12`, with an optional `14:30`.
 * Returns null when the text isn't understood.
 */
export function parseDateInput(
  input: string,
  today: number,
): { abs: number; minutes: number | null } | null {
  let text = input.trim().toLowerCase();
  let minutes: number | null = null;
  const time = text.match(/(?:^|\s)(\d{1,2}):(\d{2})$/);
  if (time) {
    minutes = Number(time[1]) * 60 + Number(time[2]);
    text = text.slice(0, time.index).trim();
  }
  const abs = parseDatePart(text, today);
  return abs === null ? null : { abs, minutes };
}

function parseDatePart(text: string, today: number): number | null {
  if (text === "" || text === "." || text === "today") {
    return today;
  }
  if (text === "tomorrow") {
    return today + 1;
  }
  if (text === "yesterday") {
    return today - 1;
  }
  const relative = text.match(/^([+-])(\d+)([dwmy]?)$/);
  if (relative) {
    const n = Number(relative[2]) * (relative[1] === "-" ? -1 : 1);
    switch (relative[3]) {
      case "w":
        return today + n * 7;
      case "m":
        return addMonths(today, n);
      case "y":
        return addMonths(today, n * 12);
      default:
        return today + n;
    }
  }
  const day = DAY_SHORT.findIndex((name) =>
    text.startsWith(name.toLowerCase()),
  );
  if (day >= 0) {
    return today + ((day - weekday(today) + 7) % 7);
  }
  const full = text.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
  if (full) {
    return toAbs(Number(full[1]), Number(full[2]), Number(full[3]));
  }
  const monthDay = text.match(/^(\d{1,2})-(\d{1,2})$/);
  if (monthDay) {
    const { y } = fromAbs(today);
    const abs = toAbs(y, Number(monthDay[1]), Number(monthDay[2]));
    return abs < today
      ? toAbs(y + 1, Number(monthDay[1]), Number(monthDay[2]))
      : abs;
  }
  const dayOnly = text.match(/^(\d{1,2})$/);
  if (dayOnly) {
    const { y, m } = fromAbs(today);
    const abs = toAbs(y, m, Number(dayOnly[1]));
    return abs < today ? addMonths(abs, 1) : abs;
  }
  return null;
}

export function formatStamp(abs: number, minutes: number | null): string {
  if (minutes === null) {
    return `<${orgDate(abs)}>`;
  }
  const h = String(Math.floor(minutes / 60)).padStart(2, "0");
  const m = String(minutes % 60).padStart(2, "0");
  return `<${orgDate(abs)} ${h}:${m}>`;
}

export { isoDate };
