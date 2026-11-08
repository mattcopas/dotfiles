// Org table alignment and cell movement. Formulas are out of scope: a #+TBLFM
// line is left untouched and nothing is recalculated.

const ROW = /^\s*\|/;
const HLINE = /^\s*\|-/;

export function isTableLine(line: string | undefined): boolean {
  return line !== undefined && ROW.test(line);
}

export function tableBounds(lines: string[], line: number) {
  let start = line;
  while (start > 0 && isTableLine(lines[start - 1])) {
    start--;
  }
  let end = line + 1;
  while (end < lines.length && isTableLine(lines[end])) {
    end++;
  }
  return { start, end };
}

function cells(line: string): string[] {
  const body = line.trim().replace(/^\|/, "").replace(/\|\s*$/, "");
  return body.split("|").map((cell) => cell.trim());
}

const NUMERIC =
  /^([><]?[-+]?[0-9.,]+[eE]?[-+]?[0-9]*%?|[<>]?[-+]?0[xX][0-9a-fA-F.]+|[<>]?[-+]?[0-9]+(?:[.,][0-9]*)?[-+]?[0-9]*[KMGTPkmgtp]?)$/;

/** Aligns one table, right-aligning columns that are mostly numbers, as org does. */
export function alignTable(lines: string[], start: number, end: number): string[] {
  const rows = lines.slice(start, end);
  const indent = rows[0].match(/^\s*/)?.[0] ?? "";
  const parsed = rows.map((row) => (HLINE.test(row) ? null : cells(row)));
  const columns = parsed.reduce(
    (most, row) => Math.max(most, row ? row.length : 0),
    0,
  );
  const widths = new Array<number>(columns).fill(1);
  const numbers = new Array<number>(columns).fill(0);
  const filled = new Array<number>(columns).fill(0);
  for (const row of parsed) {
    if (!row) {
      continue;
    }
    row.forEach((cell, i) => {
      widths[i] = Math.max(widths[i], cell.length);
      if (cell) {
        filled[i]++;
        if (NUMERIC.test(cell)) {
          numbers[i]++;
        }
      }
    });
  }
  const right = numbers.map((count, i) => filled[i] > 0 && count / filled[i] > 0.5);
  const hline = `${indent}|${widths.map((w) => "-".repeat(w + 2)).join("+")}|`;
  return rows.map((_, r) => {
    const row = parsed[r];
    if (!row) {
      return hline;
    }
    const out = widths.map((width, i) => {
      const cell = row[i] ?? "";
      return ` ${right[i] ? cell.padStart(width, " ") : cell.padEnd(width, " ")} `;
    });
    return `${indent}|${out.join("|")}|`;
  });
}

export function alignTableAt(text: string, line: number): string {
  const lines = text.split("\n");
  if (!isTableLine(lines[line])) {
    return text;
  }
  const { start, end } = tableBounds(lines, line);
  const aligned = alignTable(lines, start, end);
  lines.splice(start, end - start, ...aligned);
  return lines.join("\n");
}

function cellStarts(line: string): number[] {
  const starts: number[] = [];
  for (let i = 0; i < line.length; i++) {
    if (line[i] === "|" && i < line.trimEnd().length - 1) {
      starts.push(line[i + 1] === " " ? i + 2 : i + 1);
    }
  }
  return starts;
}

/**
 * Finds the next cell after a column, skipping horizontal rules. Reaching the end
 * of the table means a new row is needed, reported with `addRow`.
 */
export function nextCell(
  lines: string[],
  line: number,
  column: number,
): { line: number; column: number; addRow: boolean } {
  const onRow = cellStarts(lines[line]).filter((start) => start > column);
  if (!HLINE.test(lines[line]) && onRow.length) {
    return { line, column: onRow[0], addRow: false };
  }
  let at = line + 1;
  while (at < lines.length && HLINE.test(lines[at])) {
    at++;
  }
  if (at < lines.length && isTableLine(lines[at])) {
    return { line: at, column: cellStarts(lines[at])[0] ?? 0, addRow: false };
  }
  return { line: at, column: 0, addRow: true };
}

/** An empty row shaped like the row above it. */
export function blankRow(line: string): string {
  return line.replace(/[^|\s]/g, " ").replace(/-/g, " ");
}
