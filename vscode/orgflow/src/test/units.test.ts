// Behaviour org doesn't generate a golden file for, and edge cases around it.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { describe, test } from "node:test";
import { clockFromDate, formatDate, isoWeek, toAbs, addMonths, fromAbs, weekday } from "../org/date";
import {
  changePriority,
  minimalEdit,
  moveSubtree,
  setPlanning,
  setTags,
  setTodo,
  shiftHeadings,
  shiftPlanning,
} from "../org/edits";
import { fileNameToMonth, journalFileName, latestDayBefore } from "../org/journal";
import { matches, parseMatch } from "../org/match";
import { headingAt, makeConfig, parseOrg } from "../org/parser";
import { alignTableAt, blankRow, nextCell } from "../org/table";
import {
  findTimestamps,
  nextOccurrence,
  parseDateInput,
  parseTimestamp,
  previousOccurrence,
  repeatedDate,
} from "../org/timestamp";
import { discoverProjects, sortProjects } from "../projects";

const manifest = JSON.parse(readFileSync(join(__dirname, "..", "..", "package.json"), "utf8"));
const config = makeConfig(
  manifest.contributes.configuration.properties["orgflow.todoKeywords"].default,
);
const clock = { today: toAbs(2026, 11, 11), minutes: 630 };

describe("dates", () => {
  test("round trips through civil dates, including leap days", () => {
    for (const [y, m, d] of [[2024, 2, 29], [1970, 1, 1], [2000, 3, 1], [2026, 12, 31]]) {
      assert.deepEqual(fromAbs(toAbs(y, m, d)), { y, m, d });
    }
  });

  test("weekdays and ISO weeks", () => {
    assert.equal(weekday(toAbs(2026, 11, 11)), 3);
    assert.equal(isoWeek(toAbs(2026, 11, 11)), 46);
    assert.equal(isoWeek(toAbs(2027, 1, 1)), 53);
    assert.equal(isoWeek(toAbs(2024, 12, 30)), 1);
  });

  test("adding months clamps to a shorter month", () => {
    assert.deepEqual(fromAbs(addMonths(toAbs(2026, 1, 31), 1)), { y: 2026, m: 2, d: 28 });
    assert.deepEqual(fromAbs(addMonths(toAbs(2026, 12, 15), 1)), { y: 2027, m: 1, d: 15 });
    assert.deepEqual(fromAbs(addMonths(toAbs(2026, 1, 15), -1)), { y: 2025, m: 12, d: 15 });
  });

  test("the clock reads local time, not UTC", () => {
    assert.deepEqual(clockFromDate(new Date(2026, 10, 11, 23, 59)), {
      today: toAbs(2026, 11, 11),
      minutes: 23 * 60 + 59,
    });
  });

  test("%e pads with a space, and names stay English", () => {
    assert.equal(formatDate("%a %e %b %Y", toAbs(2026, 11, 8)), "Sun  8 Nov 2026");
    assert.equal(formatDate("%H:%M", toAbs(2026, 11, 8), 65), "01:05");
  });
});

describe("timestamps", () => {
  test("reads every part", () => {
    const ts = parseTimestamp("<2026-11-11 Wed 09:30-10:15 ++1w -3d>");
    assert.ok(ts);
    assert.equal(ts.abs, toAbs(2026, 11, 11));
    assert.equal(ts.minutes, 570);
    assert.equal(ts.endMinutes, 615);
    assert.deepEqual(ts.repeater, { type: "++", n: 1, unit: "w" });
    assert.deepEqual(ts.warning, { once: false, n: 3, unit: "d" });
  });

  test("works without a weekday name, and tells active from inactive", () => {
    assert.equal(parseTimestamp("<2026-11-11>")?.abs, toAbs(2026, 11, 11));
    assert.equal(parseTimestamp("[2026-11-11 Wed]")?.active, false);
    assert.equal(parseTimestamp("<2026-11-11 Wed]"), null);
  });

  test("marks both ends of a range", () => {
    const stamps = findTimestamps("<2026-11-11 Wed>--<2026-11-13 Fri>");
    assert.deepEqual(stamps.map((s) => s.inRange), [true, true]);
  });

  test("occurrences of a repeater", () => {
    const ts = parseTimestamp("<2026-11-02 Mon +1w>");
    assert.ok(ts);
    assert.equal(nextOccurrence(ts, toAbs(2026, 11, 10)), toAbs(2026, 11, 16));
    assert.equal(nextOccurrence(ts, toAbs(2026, 11, 9)), toAbs(2026, 11, 9));
    assert.equal(previousOccurrence(ts, toAbs(2026, 11, 10)), toAbs(2026, 11, 9));
    assert.equal(nextOccurrence(ts, toAbs(2026, 1, 1)), ts.abs);
  });

  test("monthly occurrences clamp", () => {
    const ts = parseTimestamp("<2026-01-31 Sat +1m>");
    assert.ok(ts);
    assert.equal(nextOccurrence(ts, toAbs(2026, 2, 10)), toAbs(2026, 2, 28));
  });

  test("a catch-up repeater lands strictly after today", () => {
    const ts = parseTimestamp("<2026-11-04 Wed ++1w>");
    assert.ok(ts);
    assert.equal(repeatedDate(ts, clock), toAbs(2026, 11, 18));
  });

  test("date prompt", () => {
    const today = clock.today; // Wednesday
    const abs = (text: string) => parseDateInput(text, today)?.abs;
    assert.equal(abs("+1d"), today + 1);
    assert.equal(abs("-2d"), today - 2);
    assert.equal(abs("+2w"), today + 14);
    assert.equal(abs("."), today);
    assert.equal(abs(""), today);
    assert.equal(abs("tomorrow"), today + 1);
    assert.equal(abs("fri"), today + 2);
    assert.equal(abs("mon"), today + 5);
    assert.equal(abs("wed"), today);
    assert.equal(abs("2027-01-02"), toAbs(2027, 1, 2));
    assert.equal(abs("12-25"), toAbs(2026, 12, 25));
    assert.equal(abs("01-02"), toAbs(2027, 1, 2));
    assert.equal(abs("20"), toAbs(2026, 11, 20));
    assert.equal(abs("3"), toAbs(2026, 12, 3));
    assert.equal(parseDateInput("+1d 14:30", today)?.minutes, 870);
    assert.equal(parseDateInput("nonsense", today), null);
  });
});

describe("parser", () => {
  const doc = parseOrg(
    [
      "#+FILETAGS: :top:",
      "#+CATEGORY: cat",
      "* IN PROGRESS [#A] Multi word :one:two:",
      "SCHEDULED: <2026-11-11 Wed> DEADLINE: <2026-11-12 Thu>",
      ":PROPERTIES:",
      ":OWNER: me",
      ":CATEGORY: own",
      ":END:",
      "** INPROGRESS not a keyword",
      "** [ ] checkbox state",
      "** [X] done checkbox",
      "*bold* is not a heading",
      "* :onlytag:",
      "* ",
    ].join("\n"),
    config,
    "file",
  );
  const [first, notKeyword, checkbox, done, onlyTag, empty] = doc.headings;

  test("keyword with a space, priority, title and tags", () => {
    assert.equal(first.keyword, "IN PROGRESS");
    assert.equal(first.priority, "A");
    assert.equal(first.title, "Multi word");
    assert.deepEqual(first.localTags, ["one", "two"]);
    assert.deepEqual(first.inheritedTags, ["top"]);
  });

  test("a keyword needs a word boundary", () => {
    assert.equal(notKeyword.keyword, null);
    assert.equal(notKeyword.title, "INPROGRESS not a keyword");
  });

  test("bracket keywords", () => {
    assert.equal(checkbox.keyword, "[ ]");
    assert.equal(done.keyword, "[X]");
    assert.ok(config.doneWords.has("[X]"));
  });

  test("planning and properties", () => {
    assert.equal(first.scheduled?.abs, toAbs(2026, 11, 11));
    assert.equal(first.deadline?.abs, toAbs(2026, 11, 12));
    assert.equal(first.properties.get("OWNER"), "me");
  });

  test("tags inherit through levels, and category through parents", () => {
    assert.deepEqual(notKeyword.inheritedTags, ["top", "one", "two"]);
    assert.equal(first.category, "own");
    assert.equal(notKeyword.category, "own");
    assert.equal(onlyTag.category, "cat");
  });

  test("structure", () => {
    assert.equal(doc.headings.length, 6);
    assert.equal(first.subtreeEnd, onlyTag.line);
    assert.equal(first.entryEnd, notKeyword.line);
    assert.equal(done.entryEnd, onlyTag.line, "*bold* stays inside the entry");
    assert.deepEqual(onlyTag.localTags, ["onlytag"]);
    assert.equal(empty.title, "");
    assert.equal(headingAt(doc, 0), undefined);
    assert.equal(headingAt(doc, 4), first);
  });

  test("sequence parsing", () => {
    assert.equal(config.keys.get("IN PROGRESS"), "p");
    assert.equal(config.keys.has("LOOP"), false);
    assert.ok(config.doneWords.has("OKAY"));
    assert.ok(!config.todoWords.has("OKAY"));
    assert.deepEqual(makeConfig([["A", "B"]]).sequences, [{ todo: ["A"], done: ["B"] }]);
  });
});

describe("match expressions", () => {
  const doc = parseOrg(
    [
      "#+FILETAGS: :work:",
      "* TODO [#A] One :urgent:",
      "SCHEDULED: <2026-11-11 Wed>",
      ":PROPERTIES:",
      ":EFFORT: 5",
      ":END:",
      "* DONE Two",
      "SCHEDULED: <2026-11-11 Wed 09:00>",
      "* Three",
    ].join("\n"),
    config,
  );
  const hit = (expression: string, index: number, todoOnly = false) =>
    matches(parseMatch(expression, todoOnly), doc.headings[index], config, clock);

  test("tags, negation, and, or", () => {
    assert.ok(hit("work", 0));
    assert.ok(hit("+work+urgent", 0));
    assert.ok(!hit("+work-urgent", 0));
    assert.ok(hit("work&urgent", 0));
    assert.ok(hit("missing|urgent", 0));
    assert.ok(!hit("urgent", 1));
  });

  test("TODO, PRIORITY with org's default, LEVEL and properties", () => {
    assert.ok(hit('TODO="TODO"', 0));
    assert.ok(hit('PRIORITY="A"', 0));
    assert.ok(hit('PRIORITY="B"', 2));
    assert.ok(hit("LEVEL=1", 0));
    assert.ok(hit("EFFORT>3", 0));
    assert.ok(!hit("EFFORT>9", 0));
    assert.ok(hit('TODO<>"DONE"', 0));
    assert.ok(hit('TODO={T.*}', 0));
  });

  test("a stamp with a time doesn't equal <today>", () => {
    assert.ok(hit('SCHEDULED="<today>"', 0));
    assert.ok(!hit('SCHEDULED="<today>"', 1));
    assert.ok(hit('SCHEDULED<="<tomorrow>"', 1));
    assert.ok(!hit('SCHEDULED="<today>"', 2));
    assert.ok(hit('SCHEDULED<>"<today>"', 2));
  });

  test("todo-only and the / part", () => {
    assert.ok(!hit("work", 1, true));
    assert.ok(hit("work", 0, true));
    assert.ok(!hit("work", 2, true));
    assert.ok(hit("work/DONE", 1));
    assert.ok(!hit("work/DONE", 0));
    assert.ok(hit("work/!", 0));
    assert.ok(!hit("work/!", 1));
  });

  test("a bad expression fails loudly", () => {
    assert.throws(() => parseMatch("+work+=="));
  });
});

describe("edits", () => {
  test("minimalEdit only spans the change", () => {
    assert.equal(minimalEdit("same", "same"), null);
    assert.deepEqual(minimalEdit("abcdef", "abXdef"), { start: 2, end: 3, text: "X" });
    assert.deepEqual(minimalEdit("abc", "abcd"), { start: 3, end: 3, text: "d" });
    assert.deepEqual(minimalEdit("abcd", "abc"), { start: 3, end: 4, text: "" });
    assert.deepEqual(minimalEdit("aaa", "aaaa"), { start: 3, end: 3, text: "a" });
  });

  test("setting a keyword keeps tag spacing and everything else", () => {
    const text = "* TODO Title     :tag:\nBody\n";
    assert.equal(setTodo(text, 0, "IN PROGRESS", config, clock), "* IN PROGRESS Title     :tag:\nBody\n");
    assert.equal(setTodo(text, 0, null, config, clock), "* Title     :tag:\nBody\n");
    assert.equal(setTodo("* Title", 0, "TODO", config, clock), "* TODO Title");
    assert.equal(setTodo("* TODO", 0, "DONE", config, clock), "* DONE");
    assert.equal(setTodo("* IN REVIEW x", 0, "TODO", config, clock), "* TODO x");
  });

  test("only leaving a not-done state triggers a repeat", () => {
    const text = "* DONE x\nSCHEDULED: <2026-11-04 Wed +1w>\n";
    assert.equal(setTodo(text, 0, "KILL", config, clock), "* KILL x\nSCHEDULED: <2026-11-04 Wed +1w>\n");
  });

  test("a repeater returns to the head of the matching sequence", () => {
    const text = "* [-] x\nSCHEDULED: <2026-11-04 Wed +1w>\n";
    assert.equal(setTodo(text, 0, "[X]", config, clock), "* [ ] x\nSCHEDULED: <2026-11-11 Wed +1w>\n");
  });

  test("an edit on a non-heading line refuses", () => {
    assert.throws(() => setTodo("text", 0, "TODO", config, clock));
  });

  test("planning is added, replaced and ordered", () => {
    assert.equal(
      setPlanning("* x\nbody", 0, "DEADLINE", clock.today, 870, config),
      "* x\nDEADLINE: <2026-11-11 Wed 14:30>\nbody",
    );
    assert.equal(
      setPlanning("* x\nSCHEDULED: <2026-01-01 Thu>", 0, "DEADLINE", clock.today, null, config),
      "* x\nSCHEDULED: <2026-01-01 Thu> DEADLINE: <2026-11-11 Wed>",
    );
  });

  test("shifting planning keeps the rest of the stamp", () => {
    assert.equal(
      shiftPlanning("* x\nSCHEDULED: <2026-11-11 Wed 09:00 +1w>", 0, "SCHEDULED", 1, config),
      "* x\nSCHEDULED: <2026-11-12 Thu 09:00 +1w>",
    );
    assert.equal(shiftPlanning("* x", 0, "SCHEDULED", 1, config), null);
  });

  test("priority steps through the range and off the end", () => {
    const step = (text: string, direction: "up" | "down") =>
      changePriority(text, 0, direction, config);
    assert.equal(step("* TODO x", "up"), "* TODO [#B] x");
    assert.equal(step("* TODO [#B] x", "up"), "* TODO [#A] x");
    assert.equal(step("* TODO [#A] x", "up"), "* TODO x");
    assert.equal(step("* TODO [#B] x", "down"), "* TODO [#C] x");
    assert.equal(step("* TODO [#C] x", "down"), "* TODO x");
    assert.equal(step("* x :tag:", "down"), "* [#B] x :tag:");
  });

  test("tags are set and cleared", () => {
    assert.equal(setTags("* x", 0, ["a", "b"], config), "* x :a:b:");
    assert.equal(setTags("* x    :old:", 0, ["new"], config), "* x :new:");
    assert.equal(setTags("* x :old:", 0, [], config), "* x");
  });

  test("moving the last subtree keeps the final newline in place", () => {
    const moved = moveSubtree("* a\nbody\n* b\n", 0, "down", config);
    assert.equal(moved.text, "* b\n* a\nbody\n");
    assert.equal(moved.line, 1);
    const up = moveSubtree("* a\n* b\nbody\n", 1, "up", config);
    assert.equal(up.text, "* b\nbody\n* a\n");
  });

  test("moving reports the new line, and survives a missing final newline", () => {
    const text = "* a\n* b\nbody";
    const moved = moveSubtree(text, 0, "down", config);
    assert.equal(moved.text, "* b\nbody\n* a");
    assert.equal(moved.line, 2);
    assert.equal(moved.text.split("\n")[moved.line], "* a");
    const back = moveSubtree(moved.text, 2, "up", config);
    assert.equal(back.line, 0);
    assert.equal(back.text, text);
  });
});

describe("tables", () => {
  test("alignment is idempotent", () => {
    const once = alignTableAt("| a | bb |\n|--\n| ccc | 1 |\n", 0);
    assert.equal(alignTableAt(once, 0), once);
  });

  test("cell movement skips rules and asks for a row at the end", () => {
    const lines = ["| a | b |", "|---+---|", "| c | d |", "after"];
    assert.deepEqual(nextCell(lines, 0, 2), { line: 0, column: 6, addRow: false });
    assert.deepEqual(nextCell(lines, 0, 6), { line: 2, column: 2, addRow: false });
    assert.deepEqual(nextCell(lines, 2, 6), { line: 3, column: 0, addRow: true });
  });

  test("a new row copies the shape", () => {
    assert.equal(blankRow("| ab | c |"), "|    |   |");
  });
});

describe("journal files", () => {
  const journal = { fileFormat: "%b-%Y.org", dateFormat: "%a %e %b %Y", carryover: "" };

  test("names both ways", () => {
    assert.equal(journalFileName(toAbs(2026, 11, 8), journal), "Nov-2026.org");
    assert.equal(fileNameToMonth("Nov-2026.org", journal), toAbs(2026, 11, 1));
    assert.equal(fileNameToMonth("notes.org", journal), null);
    assert.equal(fileNameToMonth("Xyz-2026.org", journal), null);
  });

  test("finds the most recent earlier day", () => {
    const text = "* a\n:PROPERTIES:\n:CREATED:  20261103\n:END:\n* b\n:PROPERTIES:\n:CREATED:  20261120\n:END:\n";
    assert.equal(latestDayBefore(text, toAbs(2026, 11, 11), config), toAbs(2026, 11, 3));
    assert.equal(latestDayBefore(text, toAbs(2026, 11, 1), config), null);
  });
});

describe("projects", () => {
  const tree: Record<string, string[]> = {
    "/h/git": ["alpha", "group", "node_modules", ".hidden", "plain"],
    "/h/git/group": ["beta", "gamma"],
    "/h/git/group/gamma": ["deep"],
    "/h/git/alpha": ["nested"],
    "/h/config": ["nvim", "other"],
  };
  const repos = new Set(["/h/git/alpha", "/h/git/alpha/nested", "/h/git/group/beta", "/h/git/group/gamma/deep", "/h/git/node_modules", "/h/git/.hidden", "/h/config/nvim", "/h/solo"]);
  const reader = {
    directories: async (path: string) => tree[path] ?? [],
    isRepository: async (path: string) => repos.has(path),
  };

  test("recursive roots stop at a repository and skip noise", async () => {
    const found = await discoverProjects([{ path: "/h/git", recursive: true }], reader);
    assert.deepEqual(found.sort(), ["/h/git/alpha", "/h/git/group/beta", "/h/git/group/gamma/deep"]);
  });

  test("plain roots check direct children only", async () => {
    const found = await discoverProjects([{ path: "/h/config", recursive: false }], reader);
    assert.deepEqual(found, ["/h/config/nvim"]);
    const nested = await discoverProjects([{ path: "/h/git", recursive: false }], reader);
    assert.deepEqual(nested, ["/h/git/alpha"]);
  });

  test("a root can be a repository, and a missing root is harmless", async () => {
    assert.deepEqual(await discoverProjects([{ path: "/h/solo", recursive: true }], reader), ["/h/solo"]);
    assert.deepEqual(await discoverProjects([{ path: "/nope", recursive: true }], reader), []);
  });

  test("depth is limited", async () => {
    const found = await discoverProjects([{ path: "/h/git", recursive: true }], reader, 2);
    assert.ok(!found.includes("/h/git/group/gamma/deep"));
    assert.ok(found.includes("/h/git/group/beta"));
  });

  test("recent first, then alphabetical", () => {
    assert.deepEqual(sortProjects(["/c", "/a", "/b", "/d"], ["/d", "/b"]), ["/d", "/b", "/a", "/c"]);
  });
});

describe("round trip on real org files", () => {
  // Read-only, and only on a machine that has these files. Nothing is written or copied.
  const dirs = ["git/private-personal", "git/private-work", "git/private-client", "git/journal"]
    .map((dir) => join(homedir(), dir))
    .filter(existsSync);
  const files: string[] = [];
  const walkDir = (dir: string) => {
    for (const name of readdirSync(dir)) {
      if (name === ".git") {
        continue;
      }
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        walkDir(path);
      } else if (name.endsWith(".org")) {
        files.push(path);
      }
    }
  };
  dirs.forEach(walkDir);

  test("parsing loses nothing, and a no-op edit is byte-identical", { skip: files.length === 0 }, () => {
    for (const file of files) {
      const text = readFileSync(file, "utf8");
      const doc = parseOrg(text, config);
      assert.equal(doc.lines.join("\n"), text.replace(/\r\n/g, "\n"), file);
      for (const heading of doc.headings) {
        const same = setTodo(text.replace(/\r\n/g, "\n"), heading.line, heading.keyword, config, clock);
        // Setting the current state again must change nothing except repeating items.
        if (!heading.keyword || !config.doneWords.has(heading.keyword)) {
          assert.equal(same, text.replace(/\r\n/g, "\n"), `${file}:${heading.line + 1}`);
        }
      }
    }
  });
});

describe("agenda grammar", () => {
  const grammar = JSON.parse(readFileSync(join(__dirname, "../../syntaxes/org-agenda.tmLanguage.json"), "utf8"));
  const prefix = new RegExp(grammar.repository.item.patterns[0].match.replace("\\G", "^"));
  const parts = (line: string) => {
    const match = line.slice(2).match(prefix);
    assert.ok(match, line);
    return { category: match[1], time: match[2], leader: match[3], done: match[4], todo: match[5], rest: line.slice(2 + match[0].length) };
  };

  test("only the item's own keyword is a keyword", () => {
    const line = parts("  all:        TODO make new items have TODO status and WAIT for DONE");
    assert.equal(line.todo, "TODO");
    assert.equal(line.rest, " make new items have TODO status and WAIT for DONE");
  });

  test("a title that merely contains a keyword has none", () => {
    const line = parts("  all:        Check the TODO list");
    assert.equal(line.todo, undefined);
    assert.equal(line.done, undefined);
  });

  test("a word that starts with a keyword isn't one", () => {
    assert.equal(parts("  all:        TODOS for later").todo, undefined);
    assert.equal(parts("  all:        NOTES for later").done, undefined);
  });

  test("the keyword is still found after a time and a leader", () => {
    assert.deepEqual(parts("  work:        8:00...... Scheduled:  IN PROGRESS Task"), {
      category: "work:", time: "8:00......", leader: "Scheduled:", done: undefined, todo: "IN PROGRESS", rest: " Task",
    });
    assert.equal(parts("  work:       14:00-15:30 DONE Task").done, "DONE");
    assert.equal(parts("  work:       In   3 d.:  [ ] Task").todo, "[ ]");
    assert.equal(parts("  work:        2 d. ago:  KILL Task").done, "KILL");
    assert.equal(parts("  work:       Sched. 2x:  WAIT Task").todo, "WAIT");
  });

  test("every item in the real org output has its keyword in the prefix", () => {
    const walk = (dir: string): string[] =>
      readdirSync(dir, { withFileTypes: true }).flatMap((entry) =>
        entry.isDirectory() ? walk(join(dir, entry.name)) : [join(dir, entry.name)],
      );
    const keyword = /\s(?:TODO|IN PROGRESS|IN REVIEW|LOOP|STRT|WAIT|HOLD|IDEA|DONE|KILL|OKAY|YES|NO)\s/;
    let found = 0;
    for (const file of walk(join(__dirname, "../../test/golden/expected"))) {
      for (const line of readFileSync(file, "utf8").split("\n")) {
        if (/^ {2}\S+:\s/.test(line) && keyword.test(line)) {
          const item = parts(line);
          assert.ok(item.todo || item.done, line);
          found += 1;
        }
      }
    }
    assert.ok(found > 10, `only ${found} lines`);
});
});

describe("shifting headings in a range", () => {
  const config = makeConfig([["TODO", "|", "DONE"]]);
  const text = "* One\nbody\n** TODO Two\n  indented\n* Three\n";

  test("adds a star to each heading and leaves other lines alone", () => {
    assert.equal(shiftHeadings(text, 0, 4, 1, config), "** One\nbody\n*** TODO Two\n  indented\n** Three\n");
  });

  test("only touches the range", () => {
    assert.equal(shiftHeadings(text, 2, 3, 1, config), "* One\nbody\n*** TODO Two\n  indented\n* Three\n");
  });

  test("level 1 headings can't lose their star", () => {
    assert.equal(shiftHeadings(text, 0, 4, -1, config), "* One\nbody\n* TODO Two\n  indented\n* Three\n");
  });
});
