// Calendar arithmetic on whole days ("abs" = days since 1970-01-01). Everything
// goes through civil dates rather than Date objects, so timezones and daylight
// saving can't shift an agenda day. Names are fixed to English on purpose: org
// files must not change with the system locale.

export const DAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
export const DAY_LONG = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];
export const MONTH_SHORT = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];
export const MONTH_LONG = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

export interface Civil {
  y: number;
  m: number; // 1-12
  d: number;
}

export function toAbs(y: number, m: number, d: number): number {
  const yy = m <= 2 ? y - 1 : y;
  const era = Math.floor(yy / 400);
  const yoe = yy - era * 400;
  const doy = Math.floor((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
  const doe = yoe * 365 + Math.floor(yoe / 4) - Math.floor(yoe / 100) + doy;
  return era * 146097 + doe - 719468;
}

export function fromAbs(abs: number): Civil {
  const z = abs + 719468;
  const era = Math.floor(z / 146097);
  const doe = z - era * 146097;
  const yoe = Math.floor(
    (doe -
      Math.floor(doe / 1460) +
      Math.floor(doe / 36524) -
      Math.floor(doe / 146096)) /
      365,
  );
  const doy = doe - (365 * yoe + Math.floor(yoe / 4) - Math.floor(yoe / 100));
  const mp = Math.floor((5 * doy + 2) / 153);
  const d = doy - Math.floor((153 * mp + 2) / 5) + 1;
  const m = mp + (mp < 10 ? 3 : -9);
  return { y: yoe + era * 400 + (m <= 2 ? 1 : 0), m, d };
}

/** 0 = Sunday. */
export function weekday(abs: number): number {
  return ((abs % 7) + 11) % 7;
}

export function isoWeek(abs: number): number {
  const thursday = abs - ((weekday(abs) + 6) % 7) + 3;
  const { y } = fromAbs(thursday);
  return Math.floor((thursday - toAbs(y, 1, 1)) / 7) + 1;
}

function daysInMonth(y: number, m: number): number {
  return toAbs(m === 12 ? y + 1 : y, m === 12 ? 1 : m + 1, 1) - toAbs(y, m, 1);
}

/** Adds months, clamping to the end of a shorter month as org does. */
export function addMonths(abs: number, months: number): number {
  const { y, m, d } = fromAbs(abs);
  const total = y * 12 + (m - 1) + months;
  const ny = Math.floor(total / 12);
  const nm = total - ny * 12 + 1;
  return toAbs(ny, nm, Math.min(d, daysInMonth(ny, nm)));
}

export function isoDate(abs: number): string {
  const { y, m, d } = fromAbs(abs);
  return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

/** Date plus weekday as org writes it, for example `2026-11-11 Wed`. */
export function orgDate(abs: number): string {
  return `${isoDate(abs)} ${DAY_SHORT[weekday(abs)]}`;
}

export interface Clock {
  today: number;
  /** Minutes since midnight. */
  minutes: number;
}

export function clockFromDate(date: Date): Clock {
  return {
    today: toAbs(date.getFullYear(), date.getMonth() + 1, date.getDate()),
    minutes: date.getHours() * 60 + date.getMinutes(),
  };
}

/** The subset of strftime that org-journal formats use. */
export function formatDate(format: string, abs: number, minutes = 0): string {
  const { y, m, d } = fromAbs(abs);
  const pad = (n: number) => String(n).padStart(2, "0");
  return format.replace(/%([aAbBdeHmMyY%])/g, (_, code: string) => {
    switch (code) {
      case "a":
        return DAY_SHORT[weekday(abs)];
      case "A":
        return DAY_LONG[weekday(abs)];
      case "b":
        return MONTH_SHORT[m - 1];
      case "B":
        return MONTH_LONG[m - 1];
      case "d":
        return pad(d);
      case "e":
        return String(d).padStart(2, " ");
      case "H":
        return pad(Math.floor(minutes / 60));
      case "M":
        return pad(minutes % 60);
      case "m":
        return pad(m);
      case "y":
        return pad(y % 100);
      case "Y":
        return String(y);
      default:
        return "%";
    }
  });
}
