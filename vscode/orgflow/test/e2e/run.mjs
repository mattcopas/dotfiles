// Drives the packaged VSIX in real VS Code with real VSCodeVim and the real dotfile
// settings and keybindings, using real X key events in a private Xvfb display. Results
// are read back from the DOM and from files on disk. Linux only: needs Xvfb, xdotool,
// and VSCodeVim installed in ~/.vscode-oss. Your own profile and desktop aren't touched.
//   npm run package && npm run test:e2e
import { execFileSync, spawn } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const ROOT = new URL("../..", import.meta.url).pathname;
const DOT = join(ROOT, "..");
const VERSION = JSON.parse(readFileSync(join(ROOT, "package.json"), "utf8")).version;
const W = mkdtempSync(join(tmpdir(), "orgflow-e2e-"));
const KEEP = process.env.ORGFLOW_E2E_KEEP === "1"; // Keeps screenshots and logs for inspection.
const DISPLAY = ":97";
const PORT = 9347;
const env = { ...process.env, DISPLAY };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (name, ok, detail = "") => {
  results.push(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` -- ${detail}` : ""}`);
  console.log(results.at(-1));
};

for (const d of ["data/User", "ext", "org/agenda", "journal", "shots", "projects/alpha/.git", "projects/beta/.git"]) {
  mkdirSync(join(W, d), { recursive: true });
}
writeFileSync(join(W, "projects/alpha/a-file.txt"), "alpha\n");
writeFileSync(join(W, "projects/beta/b-file.txt"), "beta\n");

const SAMPLE = `#+TITLE: Demo

* Todo list :work:
** TODO [#A] Fix the *bold* bug
SCHEDULED: <2026-11-08 Sun>
Some /italic/ text, =verbatim=, and a [[https://example.com][described link]].
** IN PROGRESS Second task
- a list item
| name | qty |
|---+---|
| apples | 3 |
* Notes
** Reference
#+BEGIN_SRC python
def hello():
    return "world"
#+END_SRC
`;
const NOTE = join(W, "org/agenda/todo.org");
writeFileSync(NOTE, SAMPLE);
const LEAK = join(W, "org/leak.org");
writeFileSync(LEAK, "* Keep me exactly like this\nA line.\n");

// The user's real settings and keybindings, plus test paths.
const strip = (t) => t.replace(/^\s*\/\/.*$/gm, "");
const settings = JSON.parse(readFileSync(join(DOT, "settings.json"), "utf8"));
Object.assign(settings, {
  "orgflow.agenda.files": [join(W, "org/agenda")],
  "orgflow.journal.directory": join(W, "journal"),
  "orgflow.projects.roots": [{ path: join(W, "projects"), recursive: true }],
  "orgflow.capture.templates": [
    { key: "w", description: "Work" },
    { key: "ww", description: "Work Todo", file: NOTE, headline: "Todo list", prepend: true },
    { key: "wt", description: "Work Todo - today", file: NOTE, headline: "Todo list", prepend: true, schedule: "+0d" },
  ],
  "security.workspace.trust.enabled": false,
  "window.restoreWindows": "none",
  "update.mode": "none",
  "extensions.autoUpdate": false,
  "telemetry.telemetryLevel": "off",
  "git.enabled": false,
  "chat.disableAIFeatures": true,
  "workbench.welcomePage.experimentalOnboarding": false,
});
writeFileSync(join(W, "data/User/settings.json"), JSON.stringify(settings, null, 2));
cpSync(join(DOT, "keybindings.json"), join(W, "data/User/keybindings.json"));

// Real VSCodeVim, copied so the user's install isn't touched, plus the packaged VSIX.
const vimDir = readdirSync(join(homedir(), ".vscode-oss/extensions")).find((n) => n.startsWith("vscodevim.vim-"));
cpSync(join(homedir(), ".vscode-oss/extensions", vimDir), join(W, "ext", vimDir), { recursive: true });
const CODE_ARGS = ["--user-data-dir", join(W, "data"), "--extensions-dir", join(W, "ext"), "--disable-gpu", "--disable-workspace-trust"];
execFileSync("code", [...CODE_ARGS, "--install-extension", join(ROOT, `orgflow-${VERSION}.vsix`), "--force"], { env, stdio: "ignore" });

const xvfb = spawn("Xvfb", [DISPLAY, "-screen", "0", "1500x950x24"], { stdio: "ignore" });
await sleep(800);
const code = spawn("code", [...CODE_ARGS, `--remote-debugging-port=${PORT}`, "--new-window", join(W, "org"), NOTE], { env, stdio: "ignore", detached: true });

let exitCode = 0;
try {
  // Connects to whichever workbench page matches, over the devtools protocol.
  async function pages() {
    const list = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
    return list.filter((t) => t.type === "page" && /workbench/.test(t.url));
  }
  function connect(url) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      let id = 0;
      const waiting = new Map();
      ws.onmessage = (e) => {
        const m = JSON.parse(e.data);
        if (m.id && waiting.has(m.id)) {
          waiting.get(m.id)(m.result);
          waiting.delete(m.id);
        }
      };
      ws.onerror = reject;
      ws.onopen = () =>
        resolve({
          send: (method, params = {}) =>
            new Promise((res) => {
              const n = ++id;
              waiting.set(n, res);
              ws.send(JSON.stringify({ id: n, method, params }));
            }),
          close: () => ws.close(),
        });
    });
  }
  let page;
  for (let i = 0; i < 60 && !page; i++) {
    await sleep(1000);
    try {
      const found = await pages();
      if (found[0]) page = await connect(found[0].webSocketDebuggerUrl);
    } catch {}
  }
  if (!page) throw new Error("VS Code never exposed a workbench page");

  const evalIn = async (p, expr) =>
    (await p.send("Runtime.evaluate", { expression: expr, returnByValue: true }))?.result?.value;
  const ev = (expr) => evalIn(page, expr);
  const shot = async (name, p = page) => {
    const r = await p.send("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(W, "shots", `${name}.png`), Buffer.from(r.data, "base64"));
  };
  const QUICK = `(() => { const w = document.querySelector('.quick-input-widget'); if (!w || w.style.display === 'none') return null; return { title: w.querySelector('.quick-input-title')?.textContent ?? '', rows: [...w.querySelectorAll('.monaco-list-row')].map(r => r.textContent).slice(0, 40) }; })()`;
  const quick = (p = page) => evalIn(p, QUICK);
  const EDITOR = `document.querySelector('.editor-group-container.active .monaco-editor .view-lines')?.innerText ?? ''`;
  const editorText = async () => String(await ev(EDITOR)).replace(/\u00a0/g, " ");
  const vimMode = () => ev(`[...document.querySelectorAll('.statusbar-item')].map(e => e.textContent).find(t => /-- .* --/.test(t)) ?? ''`);

  const windowId = () => execFileSync("xdotool", ["search", "--onlyvisible", "--class", "code"], { env }).toString().trim().split("\n").at(-1);
  const focusWin = () => {
    try { execFileSync("xdotool", ["windowfocus", "--sync", windowId()], { env, stdio: "ignore" }); } catch {}
  };
  // A real X key press. Delay 0 is the fast-typing case.
  const key = (keys, delay = 40) => execFileSync("xdotool", ["key", "--delay", String(delay), ...keys.split(" ")], { env, stdio: "ignore" });
  const type = (text) => execFileSync("xdotool", ["type", "--delay", "25", text], { env, stdio: "ignore" });
  const waitFor = async (read, ms = 8000) => {
    const start = Date.now();
    for (;;) {
      const v = await read();
      if (v) return v;
      if (Date.now() - start > ms) return v;
      await sleep(80);
    }
  };

  // Wait for startup, with both extensions running.
  await waitFor(async () => /Demo|Todo list/.test(await editorText()), 40000);
  await sleep(5000);
  focusWin();
  await sleep(500);
  const FOCUS = `(() => { const a = document.activeElement; const inEditor = a?.closest?.('.monaco-editor'); return (a?.tagName ?? '') + '.' + String(a?.className ?? '').slice(0, 40) + ' inEditor=' + !!inEditor + ' dialog=' + !!document.querySelector('.monaco-dialog-modal-block, .onboarding-a-modal, [class*=onboarding]'); })()`;
  const focus = () => ev(FOCUS);
  for (let i = 0; i < 3 && /dialog=true/.test(await focus()); i++) {
    key("Escape");
    await sleep(600);
  }
  await shot("01-startup-overview");
  const startup = await editorText();
  check("file opens folded: top-level headings show", /Notes/.test(startup) && !/Second task/.test(startup), JSON.stringify(startup.slice(0, 140)));
  check("VSCodeVim is active, in Normal mode", /NORMAL/.test(await vimMode()), await vimMode());
  const tabs = await ev(`document.querySelectorAll('.tabs-container .tab').length`);
  check("no tabs are shown", tabs === 0, `tabs=${tabs}`);

  // which-key
  key("space");
  const menu = await waitFor(quick);
  await sleep(200);
  await shot("02-which-key");
  check("SPC opens the menu in org", menu?.title === "SPC" && menu.rows.some((r) => /org local/.test(r)), JSON.stringify(menu?.rows?.slice(0, 6)));
  key("Escape");
  await sleep(300);
  check("Esc closes the menu", !(await quick()));

  key("space");
  await waitFor(quick);
  key("ctrl+g");
  await sleep(300);
  check("C-g closes the menu", !(await quick()));

  key("space");
  await waitFor(quick);
  await sleep(100);
  key("p");
  await waitFor(async () => (await quick())?.title?.includes("p"));
  await sleep(150);
  await shot("03-which-key-project");
  const sub = await quick();
  check("a submenu opens on one key", /SPC p/.test(sub?.title ?? "") && sub.rows.some((r) => /Switch project/.test(r)), sub?.title);
  key("Escape");
  await sleep(300);

  // Indenting a heading changes its stars, and only its stars.
  const SHIFT = join(W, "org/shift.org");
  writeFileSync(SHIFT, "* Heading one\nbody\n** Second\n* Third\n");
  execFileSync("code", [...CODE_ARGS, "--reuse-window", SHIFT], { env, stdio: "ignore" });
  await waitFor(async () => /shift\.org/.test(await ev("document.title")), 8000);
  await sleep(1500);
  focusWin();
  key("Escape");
  await sleep(200);
  key("z shift+r");
  await sleep(500);
  const saved = async () => {
    key("Escape");
    await sleep(200);
    key("space w");
    await sleep(700);
    return readFileSync(SHIFT, "utf8");
  };
  const shiftKeys = async (keys) => {
    key(keys);
    await sleep(500);
    return saved();
  };
  key("g g");
  await sleep(300);
  check(">> adds a star", (await shiftKeys("greater greater")).startsWith("** Heading one\n"));
  check(">> again adds another", (await shiftKeys("greater greater")).startsWith("*** Heading one\n"));
  check("<< removes one", (await shiftKeys("less less")).startsWith("** Heading one\n"));
  check("<< removes the next", (await shiftKeys("less less")).startsWith("* Heading one\n"));
  check("<< stops at one star", (await shiftKeys("less less")).startsWith("* Heading one\n"));
  key("Escape");
  await sleep(300);
  key("j");
  await sleep(300);
  const indented = await shiftKeys("greater greater");
  check(">> on body text still indents", /\n +body\n/.test(indented), JSON.stringify(indented));
  check("<< on body text still unindents", (await shiftKeys("less less")).includes("\nbody\n"));
  key("g g");
  await sleep(300);
  key("shift+v j j j");
  await sleep(300);
  check("Visual > adds a star to each heading only", (await shiftKeys("greater")) === "** Heading one\nbody\n*** Second\n** Third\n");
  key("g g");
  await sleep(300);
  key("shift+v j j j");
  await sleep(300);
  check("Visual < removes them", (await shiftKeys("less")) === "* Heading one\nbody\n** Second\n* Third\n");
  key("g g");
  await sleep(300);
  key("j j");
  await sleep(300);
  key("shift+a");
  await sleep(300);
  key("Tab");
  await sleep(600);
  type("X");
  await sleep(300);
  const tabbed = await saved();
  check("TAB in Insert mode adds a star and keeps the cursor", tabbed.includes("\n*** SecondX\n"), JSON.stringify(tabbed));
  key("shift+a");
  await sleep(300);
  key("shift+Tab");
  await sleep(600);
  const untabbed = await saved();
  check("S-TAB in Insert mode removes one", untabbed.includes("\n** SecondX\n"), JSON.stringify(untabbed));
  execFileSync("code", [...CODE_ARGS, "--reuse-window", NOTE], { env, stdio: "ignore" });
  await sleep(1500);
  focusWin();
  key("Escape");
  await sleep(300);

  // TAB cycling with a real key. Put the cursor on the first heading.
  key("g g");
  await sleep(150);
  type("/Todo list");
  key("Return");
  await sleep(300);
  key("Escape");
  await sleep(200);
  key("Tab");
  await waitFor(async () => /Second task/.test(await editorText()), 3000);
  await sleep(300);
  await shot("04-tab-children");
  const children = await editorText();
  check("TAB shows children", /Second task/.test(children) && !/a list item/.test(children), "");
  key("Tab");
  await waitFor(async () => /a list item/.test(await editorText()), 3000);
  await sleep(500);
  await shot("05-tab-subtree-decorations");
  check("TAB shows the whole subtree", /a list item/.test(await editorText()));
  key("Tab");
  await waitFor(async () => !/a list item/.test(await editorText()), 3000);
  check("TAB folds again", !/a list item/.test(await editorText()));
  key("Tab");
  await sleep(250);
  key("Tab");
  await waitFor(async () => /a list item/.test(await editorText()), 3000);

  // Capture through real keys.
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("X");
  await waitFor(async () => (await quick())?.title === "Capture");
  await sleep(100);
  await shot("06-capture-menu");
  key("w");
  await waitFor(async () => /Capture w/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("w");
  await waitFor(async () => (await quick())?.title === "Work Todo");
  await sleep(150);
  type("Captured with real keys");
  key("Return");
  await sleep(800);
  check("SPC X w w captures to the file", /\* Todo list :work:\n\*\* TODO Captured with real keys\n/.test(readFileSync(NOTE, "utf8")));

  // Agenda through real keys.
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("o");
  await waitFor(async () => /SPC o/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("shift+a");
  await waitFor(async () => (await quick())?.title === "Agenda");
  await sleep(100);
  key("w");
  await waitFor(async () => /High priority/.test(await editorText()), 5000);
  await sleep(600);
  await shot("07-agenda-work");
  const agenda = await editorText();
  check("SPC o A w opens the work agenda", /High priority/.test(agenda) && /Fix the/.test(agenda), JSON.stringify(agenda.slice(0, 200)));
  const lang = await ev(`document.querySelector('.editor-group-container.active .monaco-editor')?.getAttribute('data-mode-id') ?? ''`);
  // j moves with Vim, then t opens fast TODO selection, d marks done.
  key("g g");
  await sleep(100);
  key("j");
  await sleep(200);
  key("t");
  const states = await waitFor(async () => (await quick())?.title === "TODO state" ? await quick() : null, 4000);
  await sleep(150);
  await shot("08-agenda-todo-states");
  check("t in the agenda opens the state picker, not Vim's t", !!states, `lang=${lang}`);
  key("d");
  await sleep(900);
  check("d marks the item DONE on disk", /\*\* DONE \[#A\] Fix the \*bold\* bug/.test(readFileSync(NOTE, "utf8")), readFileSync(NOTE, "utf8").split("\n").find((l) => /Fix the/.test(l)));
  await sleep(300);
  await shot("09-agenda-after-done");

  // Enter jumps to the heading.
  const before = await editorText();
  key("g g");
  await sleep(200);
  key("j");
  await sleep(200);
  type("/Second");
  key("Return");
  await sleep(300);
  key("Escape");
  await sleep(150);
  key("Return");
  await waitFor(async () => /\* Notes|Todo list/.test(await editorText()) && (await editorText()) !== before, 4000);
  await sleep(500);
  const jumped = await editorText();
  check("Enter on an agenda line opens the org file", /Second task/.test(jumped) && !/High priority/.test(jumped), "");
  await shot("10-after-jump");

  // Scheduling with keys, and structure moves.
  const todo = () => readFileSync(NOTE, "utf8");
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("m");
  await waitFor(async () => /SPC m/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("s");
  await waitFor(async () => /SPC m s/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("shift+t");
  await sleep(500);
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("w");
  await sleep(700);
  check("SPC m s T schedules for tomorrow, and SPC w saves", /IN PROGRESS Second task\nSCHEDULED: <\d{4}-\d\d-\d\d \w+>/.test(todo()), todo().split("\n").slice(4, 9).join(" | "));

  // Space in Insert mode must still type a space.
  execFileSync("xdotool", ["key", "o"], { env });
  await sleep(250);
  check("o enters Insert mode", /INSERT/.test(await vimMode()), await vimMode());
  type("words with spaces");
  key("Escape");
  await sleep(300);
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("w");
  await sleep(600);
  check("space types normally in Insert mode", /words with spaces/.test(todo()));

  // Alt keys move a subtree. Reopen a clean file for this.
  // Journal.
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("n");
  await waitFor(async () => /SPC n/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("j");
  await waitFor(async () => /SPC n j/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("j");
  await sleep(1200);
  const files = readdirSync(join(W, "journal"));
  check("SPC n j j creates this month's journal", files.length === 1 && /^[A-Z][a-z]{2}-\d{4}\.org$/.test(files[0]), files.join(","));
  const journal = files[0] ? readFileSync(join(W, "journal", files[0]), "utf8") : "";
  check("the journal entry has org-journal's format", /^\* \w{3} [ \d]\d \w{3} \d{4}\n:PROPERTIES:\n:CREATED:  \d{8}\n:END:\n\*\* \d\d:\d\d \n$/.test(journal), JSON.stringify(journal));
  await shot("11-journal");

  // Find file and project search.
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("space");
  await sleep(700);
  const finder = await quick();
  await shot("12-find-file");
  check("SPC SPC opens find-file", !!finder && finder.title !== "SPC", JSON.stringify(finder?.rows?.slice(0, 3)));
  key("Escape");
  await sleep(300);
  key("space");
  await waitFor(quick);
  await sleep(100);
  key("s");
  await waitFor(async () => /SPC s/.test((await quick())?.title ?? ""));
  await sleep(100);
  key("p");
  await sleep(700);
  const searcher = await quick();
  await shot("13-search-project");
  check("SPC s p opens project search", !!searcher, JSON.stringify(searcher?.title));
  key("Escape");
  await sleep(300);

  // The fast-typing test: yank a line so a leaked p visibly pastes, then SPC-chords at full speed.
  const leakPage = page;
  execFileSync("code", [...CODE_ARGS, "--reuse-window", LEAK], { env, stdio: "ignore" });
  await waitFor(async () => /Keep me exactly/.test(await editorText()), 6000);
  await sleep(900);
  key("g g");
  await sleep(100);
  key("y y");
  await sleep(150);
  const leakBefore = await editorText();
  const RUNS = Number(process.env.RUNS ?? 12);
  for (const delay of [0, 10, 30, 60]) {
    let reached = 0;
    for (let i = 0; i < RUNS; i++) {
      key("space p p", delay);
      const opened = await waitFor(async () => (await quick())?.title === "Switch to project", 1500);
      if (opened) reached++;
      key("Escape");
      await sleep(250);
      if (await quick()) { key("Escape"); await sleep(200); }
    }
    check(`SPC p p reaches the picker at ${delay}ms between keys (${reached}/${RUNS})`, reached === RUNS);
  }
  // A chord abandoned part way, and Esc racing the picker.
  for (let i = 0; i < 6; i++) {
    key("space p Escape", 0);
    await sleep(300);
    if (await quick()) { key("Escape"); await sleep(200); }
  }
  check("Esc during a fast chord closes the menu", !(await quick()));
  const leakAfter = await editorText();
  const dirty = await ev(`document.title.includes('●')`);
  check("fast chords never leak keys into the file", leakAfter === leakBefore && !dirty, `dirty=${dirty}`);
  // Keys must return to Vim afterwards, or the buffer would swallow normal typing.
  key("j");
  await sleep(250);
  key("k");
  await sleep(250);
  const stillNormal = /NORMAL/.test(await vimMode());
  key("i");
  await sleep(200);
  type("x");
  await sleep(200);
  key("Escape");
  await sleep(250);
  const typed = (await editorText()).includes("x* Keep") || (await editorText()).includes("x") ;
  check("Vim receives keys normally after the menu", stillNormal && typed);
  key("u");
  await sleep(300);
  await shot("14-after-fast-typing");

  // Capture and agenda chords at full speed, through the second picker.
  key("space X w w", 0);
  const fastCapture = await waitFor(async () => (await quick())?.title === "Work Todo", 2500);
  check("SPC X w w at 0ms reaches the title prompt", !!fastCapture, JSON.stringify((await quick())?.title));
  key("Escape");
  await sleep(300);
  key("space o shift+a w", 0);
  const fastAgenda = await waitFor(async () => /High priority/.test(await editorText()), 3000);
  check("SPC o A w at 0ms opens the agenda", !!fastAgenda);
  const afterFastDirty = await ev(`document.title.includes('●')`);
  check("nothing leaked during the nested fast chords", !afterFastDirty, `dirty=${afterFastDirty}`);

  // Project switching, including an already open project.
  key("space p p", 0);
  await waitFor(async () => (await quick())?.title === "Switch to project");
  await waitFor(async () => (await quick())?.rows?.some((r) => /alpha/.test(r)), 5000);
  await sleep(300);
  await shot("15-switch-project");
  const projectRows = await quick();
  check("SPC p p lists discovered projects", projectRows.rows.some((r) => /alpha/.test(r)) && projectRows.rows.some((r) => /beta/.test(r)), JSON.stringify(projectRows.rows));
  type("alpha");
  await sleep(250);
  key("Return");
  const waitNew = await waitFor(async () => (await pages()).length >= 2, 25000);
  check("choosing a project opens a new window", waitNew, `pages=${(await pages()).length}`);
  await waitFor(async () => (await pages()).some((t) => /alpha/.test(t.title)), 25000);
  // Quick Open lists only recent files until you type, so this types, like a person would.
  const findsFile = async (p) => {
    const open = await waitFor(async () => {
      const q = await quick(p);
      return q && q.title !== "SPC" ? q : null;
    }, 20000);
    if (!open) return false;
    const ids = execFileSync("xdotool", ["search", "--name", "alpha"], { env }).toString().trim().split("\n");
    execFileSync("xdotool", ["windowfocus", "--sync", ids.at(-1)], { env, stdio: "ignore" });
    await sleep(300);
    type("a-file");
    return waitFor(async () => (await quick(p))?.rows?.some((r) => /a-file/.test(r)), 6000);
  };
  let alpha;
  for (const t of await pages()) {
    if (/alpha/.test(t.title)) alpha = await connect(t.webSocketDebuggerUrl);
  }
  if (alpha) {
    const foundNew = await findsFile(alpha);
    await shot("16-new-project-find-file", alpha);
    check("find-file opens by itself in the new project window, and finds a file", !!foundNew, JSON.stringify((await quick(alpha))?.rows?.slice(0, 2)));
    await evalIn(alpha, "1");
    key("Escape");
    await sleep(400);

    // Switch away and back: the already open case, the risky one from the plan.
    const windows = execFileSync("xdotool", ["search", "--onlyvisible", "--class", "code"], { env }).toString().trim().split("\n");
    const first = windows[0];
    execFileSync("xdotool", ["windowfocus", "--sync", first], { env, stdio: "ignore" });
    await sleep(800);
    const titleBefore = (await pages()).map((t) => t.title);
    key("space p p", 0);
    await sleep(900);
    let target = null;
    for (const t of await pages()) {
      const p = await connect(t.webSocketDebuggerUrl);
      const q = await quick(p);
      if (q?.title === "Switch to project") target = p;
      else p.close();
    }
    if (target) {
      await waitFor(async () => (await quick(target))?.rows?.some((r) => /alpha/.test(r)), 4000);
      type("alpha");
      await sleep(250);
      key("Return");
      await sleep(4000);
      const after = await pages();
      check("an already open project doesn't open a second window", after.length === 2, `before=${titleBefore} after=${after.map((t) => t.title)}`);
      const a2 = await connect(after.find((t) => /alpha/.test(t.title)).webSocketDebuggerUrl);
      const foundAgain = await findsFile(a2);
      await shot("17-existing-window-find-file", a2);
      check("find-file opens in the already open project window, and finds a file", !!foundAgain, JSON.stringify((await quick(a2))?.rows?.slice(0, 2)));
    } else {
      check("the window focus test ran", false, "couldn't open the picker in the first window");
    }
  } else {
    check("the alpha window exists", false, JSON.stringify((await pages()).map((t) => t.title)));
  }
} catch (error) {
  check("the run completed", false, error.stack);
  exitCode = 1;
} finally {
  writeFileSync(join(W, "results.txt"), `${results.join("\n")}\n`);
  try { process.kill(-code.pid, "SIGTERM"); } catch {}
  await sleep(1500);
  try { process.kill(-code.pid, "SIGKILL"); } catch {}
  xvfb.kill("SIGTERM");
  const fails = results.filter((r) => r.startsWith("FAIL")).length;
  if (KEEP) {
    console.log(`Kept screenshots in ${join(W, "shots")}`);
  } else {
    rmSync(W, { recursive: true, force: true });
  }
  console.log(`\n${results.length - fails}/${results.length} passed`);
  process.exit(fails || exitCode ? 1 : 0);
}
