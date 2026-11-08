// Compares the org engine with real org-mode output captured by test/golden.
// Fixed clock used for generation: Wed 11 Nov 2026 10:30.
import assert from "node:assert/strict";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "node:test";
import { AgendaFile, AgendaView, renderView } from "../org/agenda";
import { toAbs } from "../org/date";
import {
  captureEntry,
  CaptureSpec,
  moveSubtree,
  setPlanning,
  setTodo,
  shiftHeading,
  shiftSubtree,
} from "../org/edits";
import { JournalConfig, planNewEntry } from "../org/journal";
import { makeConfig, parseOrg } from "../org/parser";
import { alignTableAt } from "../org/table";
import { formatStamp } from "../org/timestamp";

const root = join(__dirname, "..", "..");
const fixtures = join(root, "test", "fixtures");
const expected = join(root, "test", "golden", "expected");
const manifest = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const settings = manifest.contributes.configuration.properties;

const config = makeConfig(settings["orgflow.todoKeywords"].default);
const clock = { today: toAbs(2026, 11, 11), minutes: 10 * 60 + 30 };
const views: AgendaView[] = settings["orgflow.agenda.views"].default;

function read(path: string): string {
  return readFileSync(path, "utf8");
}

function agendaFiles(): AgendaFile[] {
  const files: AgendaFile[] = [];
  for (const dir of ["personal", "client", "work"]) {
    const full = join(fixtures, "agenda", dir);
    for (const name of readdirSync(full).sort()) {
      const path = join(full, name);
      if (statSync(path).isFile() && /^[^.].*\.org$/.test(name)) {
        files.push({ path, base: name.replace(/\.org$/, ""), text: read(path) });
      }
    }
  }
  return files;
}

describe("agenda views match org-agenda exactly", () => {
  for (const view of views) {
    test(`view ${view.key}: ${view.description}`, () => {
      const text = renderView(view, agendaFiles(), { config, clock, width: 80 })
        .map((line) => line.text)
        .join("\n");
      const want = read(join(expected, `agenda-${view.key}.txt`)).replace(/\n+$/, "");
      assert.equal(text, want);
    });
  }

  test("every item line points back at its heading", () => {
    const view = views.find((v) => v.key === "c") as AgendaView;
    const lines = renderView(view, agendaFiles(), { config, clock, width: 80 });
    const items = lines.filter((line) => line.target);
    assert.ok(items.length > 20);
    for (const line of items) {
      const target = line.target as NonNullable<typeof line.target>;
      const source = read(target.path).split("\n")[target.line];
      assert.equal(source, target.raw);
      assert.match(source, /^\*+ /);
    }
  });
});

describe("repeaters match org", () => {
  test("marking every fixture heading DONE", () => {
    let text = read(join(fixtures, "edits", "repeat.org"));
    const headings = parseOrg(text, config).headings.map((h) => h.line).reverse();
    for (const line of headings) {
      text = setTodo(text, line, "DONE", config, clock);
    }
    assert.equal(text, read(join(expected, "edit-repeat.org")));
  });
});

describe("scheduling matches org", () => {
  for (const [name, days] of [["today", 0], ["tomorrow", 1]] as const) {
    test(`scheduling every heading for ${name}`, () => {
      let text = read(join(fixtures, "edits", "schedule.org"));
      const headings = parseOrg(text, config).headings.map((h) => h.line).reverse();
      for (const line of headings) {
        text = setPlanning(text, line, "SCHEDULED", clock.today + days, null, config);
      }
      assert.equal(text, read(join(expected, `edit-schedule-${name}.org`)));
    });
  }

  test("rescheduling keeps a repeater", () => {
    const text = "* TODO x\nSCHEDULED: <2026-01-01 Thu +1w>\n";
    assert.equal(
      setPlanning(text, 0, "SCHEDULED", clock.today, null, config),
      "* TODO x\nSCHEDULED: <2026-11-11 Wed +1w>\n",
    );
  });
});

describe("structure edits match org", () => {
  const source = read(join(fixtures, "edits", "structure.org"));
  const line = (title: string) => {
    const found = parseOrg(source, config).headings.find((h) => h.title === title);
    return (found as { line: number }).line;
  };
  const cases: [string, () => string][] = [
    ["edit-move-down.org", () => moveSubtree(source, line("First"), "down", config).text],
    ["edit-move-second-up.org", () => moveSubtree(source, line("Second"), "up", config).text],
    ["edit-move-child-down.org", () => moveSubtree(source, line("First child"), "down", config).text],
    ["edit-move-up.org", () => moveSubtree(source, line("Second child"), "up", config).text],
    ["edit-promote.org", () => shiftHeading(source, line("First child"), -1, config)],
    ["edit-promote-subtree.org", () => shiftSubtree(source, line("First child"), -1, config)],
    ["edit-demote.org", () => shiftHeading(source, line("First"), 1, config)],
    ["edit-demote-subtree.org", () => shiftSubtree(source, line("Second child"), 1, config)],
    ["edit-demote-third.org", () => shiftHeading(source, line("Third"), 1, config)],
  ];
  for (const [file, run] of cases) {
    test(file, () => assert.equal(run(), read(join(expected, file))));
  }

  test("a subtree can't move past its parent", () => {
    assert.throws(() => moveSubtree(source, line("Second child"), "down", config));
    assert.throws(() => moveSubtree(source, line("First"), "up", config));
  });

  test("a level 1 heading can't be promoted", () => {
    assert.throws(() => shiftHeading(source, line("First"), -1, config));
  });
});

describe("capture matches org-capture", () => {
  const base =
    "#+TITLE: Capture\n\n* Before\n* Todo list\nIntro line.\n** TODO Existing one\n** TODO Existing two\nBody.\n* After\n";
  const scheduled = (title: string, days: number): Partial<CaptureSpec> => ({
    entry: `TODO ${title} `,
    extraLines: [` SCHEDULED: ${formatStamp(clock.today + days, null)}`],
  });
  const cases: [string, CaptureSpec, string][] = [
    ["ww", { headline: "Todo list", prepend: true, entry: "TODO Work plain" }, base],
    ["wt", { headline: "Todo list", prepend: true, entry: "", ...scheduled("Work today", 0) }, base],
    ["wT", { headline: "Todo list", prepend: true, entry: "", ...scheduled("Work tomorrow", 1) }, base],
    ["t", { headline: "Todo list", prepend: false, entry: "TODO Plain append" }, base],
    ["new", { headline: "Todo list", prepend: true, entry: "TODO Into new headline" }, "* Other\n"],
  ];
  for (const [name, spec, input] of cases) {
    test(`template ${name}`, () => {
      assert.equal(
        captureEntry(input, spec, config).text,
        read(join(expected, `edit-capture-${name}.org`)),
      );
    });
  }

  test("capture into an empty file", () => {
    assert.equal(
      captureEntry("", { headline: "Todo list", prepend: true, entry: "TODO x" }, config).text,
      "* Todo list\n** TODO x\n",
    );
  });

  test("the returned line is where the entry landed", () => {
    const result = captureEntry(base, { headline: "Todo list", prepend: true, entry: "TODO y" }, config);
    assert.equal(result.text.split("\n")[result.line], "** TODO y");
  });
});

describe("tables match org-table-align", () => {
  test("both fixture tables", () => {
    let text = read(join(fixtures, "edits", "table.org"));
    text = alignTableAt(text, 1);
    const second = text.split("\n").findIndex((line) => line.startsWith("|a|"));
    text = alignTableAt(text, second);
    assert.equal(text, read(join(expected, "edit-table-align.org")));
  });
});

describe("journal matches org-journal", () => {
  const journalConfig: JournalConfig = {
    fileFormat: settings["orgflow.journal.fileFormat"].default,
    dateFormat: settings["orgflow.journal.dateFormat"].default,
    carryover: settings["orgflow.journal.carryover"].default,
  };
  const at = (y: number, m: number, d: number, hh: number, mm: number) => ({
    today: toAbs(y, m, d),
    minutes: hh * 60 + mm,
  });
  const fixture = (name: string) => read(join(fixtures, "journal", name, "Nov-2026.org"));
  const want = (name: string, file: string) => read(join(expected, `journal-${name}`, file));
  const base = { config: journalConfig, orgConfig: config };

  test("a new file", () => {
    const plan = planNewEntry({ ...base, clock: at(2026, 11, 11, 14, 32), currentText: "" });
    assert.equal(plan.current, want("empty", "Nov-2026.org"));
  });

  test("a single-digit day keeps org's padding", () => {
    const plan = planNewEntry({ ...base, clock: at(2027, 3, 2, 9, 5), currentText: "" });
    assert.equal(plan.current, want("single-digit", "Mar-2027.org"));
  });

  test("carryover within a month", () => {
    const plan = planNewEntry({ ...base, clock: at(2026, 11, 11, 14, 32), currentText: fixture("inmonth") });
    assert.equal(plan.current, want("inmonth", "Nov-2026.org"));
  });

  test("carryover with nested items, shared parents and stamps", () => {
    const plan = planNewEntry({ ...base, clock: at(2026, 11, 11, 14, 32), currentText: fixture("nested") });
    // org-journal leaves one stray blank line when the item it deletes sits directly
    // above today's heading. That's a side effect, so orgflow doesn't copy it.
    const expectedText = want("nested", "Nov-2026.org").replace(
      "carryover list\n\n* Wed",
      "carryover list\n* Wed",
    );
    assert.equal(plan.current, expectedText);
  });

  test("carryover across a month boundary changes both files", () => {
    const plan = planNewEntry({
      ...base,
      clock: at(2026, 12, 1, 9, 15),
      currentText: "",
      previousText: fixture("rollover"),
    });
    assert.equal(plan.current, want("rollover", "Dec-2026.org"));
    assert.equal(plan.previous, want("rollover", "Nov-2026.org"));
  });

  test("a second entry today, with a later day already in the file", () => {
    const plan = planNewEntry({ ...base, clock: at(2026, 11, 11, 14, 32), currentText: fixture("sameday") });
    assert.equal(plan.current, want("sameday", "Nov-2026.org"));
  });

  test("two entries in a row", () => {
    const clock2 = at(2026, 11, 11, 14, 32);
    const first = planNewEntry({ ...base, clock: clock2, currentText: fixture("inmonth") });
    const second = planNewEntry({ ...base, clock: clock2, currentText: first.current });
    assert.equal(second.current, want("twice", "Nov-2026.org"));
  });

  test("the entry line points at the new entry", () => {
    const plan = planNewEntry({ ...base, clock: at(2026, 11, 11, 14, 32), currentText: fixture("nested") });
    assert.equal(plan.current.split("\n")[plan.line], "** 14:32 ");
  });
});
