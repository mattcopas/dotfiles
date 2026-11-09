#!/usr/bin/env python3
"""Real keystrokes to a real Vim in tmux, with the real .vimrc and link.sh install.

Everything happens under a throwaway HOME built like a real one, using the default
settings, so ~/git/private-work and friends are real paths inside it. Keys are sent in
one burst wherever fast typing matters. Needs tmux, git and rg. Clock: 11 Nov 2026 10:30.
"""
import datetime
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOTFILES = ROOT.parent.parent
FIXTURES = DOTFILES / "vscode/orgflow/test/fixtures"
VIM = os.environ.get("VIM", "/usr/bin/vim")
ABS_TODAY = (datetime.date(2026, 11, 11) - datetime.date(1970, 1, 1)).days

passed = 0
failures = []
home = Path(tempfile.mkdtemp(prefix="orgflow-e2e-"))
SOCKET = f"orgflow-e2e-{os.getpid()}"


def tmux(*args, **kwargs):
    return subprocess.run(["tmux", "-L", SOCKET, "-f", "/dev/null", *args], capture_output=True, text=True, **kwargs)


def screen():
    return tmux("capture-pane", "-p", "-t", "t").stdout


def send(*keys):
    """Keys in tmux names: Space, Tab, BTab, Enter, Escape, M-j. All in one burst."""
    tmux("send-keys", "-t", "t", *keys)


def type_text(text):
    tmux("send-keys", "-t", "t", "-l", text)


def wait_for(pattern, timeout=5.0, absent=False):
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = re.search(pattern, screen(), re.M)
        if bool(found) != absent:
            return True
        time.sleep(0.03)
    return False


def check(name, ok, detail=""):
    global passed
    if ok:
        passed += 1
    else:
        shown = "\n".join(line for line in screen().splitlines() if line.strip() not in ("", "~"))
        failures.append(f"FAIL {name}\n{detail}\n--- screen ---\n{shown}")


def expect(name, pattern, timeout=5.0):
    check(name, wait_for(pattern, timeout), f"expected on screen: {pattern}")


def expect_gone(name, pattern, timeout=5.0):
    check(name, wait_for(pattern, timeout, absent=True), f"expected gone: {pattern}")


def expect_file(name, path, text):
    """Waits for text to appear in a file."""
    deadline = time.time() + 5
    content = ""
    while time.time() < deadline:
        content = path.read_text() if path.exists() else ""
        if text in content:
            break
        time.sleep(0.03)
    check(name, text in content, f"expected in {path}: {text!r}\nfile:\n{content}")


def command(text):
    send("Escape")
    send(":")
    type_text(text)
    send("Enter")


def evaluate(expression):
    """Reads a value out of the running Vim through a file."""
    out = home / "eval.txt"
    out.unlink(missing_ok=True)
    command(f"call writefile([string({expression})], '{out}')")
    deadline = time.time() + 3
    while time.time() < deadline:
        if out.exists() and out.stat().st_size:
            return out.read_text().strip()
        time.sleep(0.02)
    return "<no answer>"


def check_value(name, expression, want):
    got = evaluate(expression)
    check(name, got == want, f"{expression}: got {got!r}, want {want!r}")


def start(*args, cwd=None):
    tmux("kill-session", "-t", "t")
    env = {
        "HOME": str(home),
        "TERM": "tmux-256color",
        "COLORTERM": "truecolor",
        "XDG_STATE_HOME": str(home / "state"),
    }
    prefix = ["env", "-u", "VIMINIT", *[f"{k}={v}" for k, v in env.items()]]
    cmd = [
        *prefix,
        VIM,
        "-i",
        "NONE",
        "-n",
        "--cmd",
        f"let g:orgflow_test_clock = {{'today': {ABS_TODAY}, 'minutes': 630}}",
        # Line numbers would only get in the way of matching the start of a line.
        "-c",
        "set nonumber norelativenumber",
        *args,
    ]
    tmux("new-session", "-d", "-s", "t", "-x", "130", "-y", "45", "-c", str(cwd or home), *cmd)
    tmux("set-option", "-t", "t", "status", "off")
    # Keep the pane so a crash shows what happened rather than ending the test.
    tmux("set-option", "-t", "t", "remain-on-exit", "on")
    tmux("set-option", "-s", "escape-time", "0")
    time.sleep(0.25)


def build_home():
    """A home directory set up the way link.sh sets up a real one."""
    subprocess.run(["bash", str(ROOT.parent / "link.sh")], env={**os.environ, "HOME": str(home)}, check=True, capture_output=True)
    git = home / "git"
    for source, name in [("personal", "private-personal"), ("client", "private-client"), ("work", "private-work")]:
        shutil.copytree(FIXTURES / "agenda" / source, git / name)
    (git / "journal").mkdir()
    notes = git / "proj-alpha"
    (notes / "src").mkdir(parents=True)
    (notes / "src/needle.txt").write_text("first\nthe haystack line\nlast\n")
    (notes / "README.md").write_text("# alpha\n")
    (git / "proj-beta").mkdir()
    (git / "proj-beta/beta-file.txt").write_text("beta\n")
    for repo in [notes, git / "proj-beta", git / "private-work", git / "private-client", git / "private-personal"]:
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
    (home / "doc.org").write_text(
        "#+TITLE: Doc\n"
        "* TODO First :tag:\n"
        "first body\n"
        "** Child one\n"
        "child body\n"
        "** Child two\n"
        "* Second\n"
        "*bold* and /italic/ and [[https://example.com][a link]] and [[*Second][jump]]\n"
        "* Table\n"
        "|a|bbb|\n"
        "|ccc|d|\n"
    )


def test_startup():
    start(str(home / "doc.org"))
    expect("org file opens in overview", r"^\* TODO First :tag: …")
    expect_gone("nothing wrong at startup", r"^(Error|E\d+)")
    check_value("the colorscheme loaded from the package", "g:colors_name", "'doom-one'")
    check_value("the filetype is org", "&filetype", "'org'")
    check_value("no tab line", "&showtabline", "0")
    check_value("syntax is active", "get(b:, 'current_syntax', '')", "'org'")
    check_value("nothing went to messages", "execute('messages') =~# 'E[0-9]\\+:'", "0")


def test_folding_keys():
    start(str(home / "doc.org"))
    expect("starts folded", r"^\* Second …")
    send("g", "g", "j")
    send("Tab")
    expect("TAB shows children", r"CHILDREN")
    expect("children visible", r"^\s*\*+ Child one")
    send("Tab")
    expect("TAB shows the subtree", r"SUBTREE")
    expect("body visible", r"^child body")
    send("Tab")
    expect("TAB folds", r"FOLDED")
    expect_gone("body hidden", r"^child body")
    send("BTab")
    expect("S-TAB contents", r"CONTENTS")
    send("BTab")
    expect("S-TAB show all", r"SHOW ALL")
    expect("all text visible", r"^child body")
    send("BTab")
    expect("S-TAB overview", r"OVERVIEW")
    expect_gone("back to folded", r"^child body")


def test_tab_off_a_heading():
    path = home / "plain-lines.org"
    path.write_text(
        "before any heading\n"
        "* TODO Item\n"
        "SCHEDULED: <2026-11-11 Wed>\n"
        ":PROPERTIES:\n"
        ":ID: 1\n"
        ":END:\n"
        "body text\n"
        "\n"
        "#+begin_src sh\n"
        "ls\n"
        "#+end_src\n"
        "- list item\n"
        "** Child\n"
        "  SCHEDULED: <2026-11-12 Thu>\n"
    )
    start(str(path))
    command("normal! zR")
    command("messages clear")
    for lnum, name in [
        (1, "before the first heading"),
        (3, "SCHEDULED"),
        (7, "body text"),
        (8, "a blank line"),
        (10, "inside a block"),
        (12, "a list item"),
        (14, "indented SCHEDULED"),
    ]:
        command(f"call cursor({lnum}, 1)")
        send("Tab")
        check_value(f"TAB stays on {name}", "line('.')", str(lnum))
    for lnum, name in [(4, "a drawer"), (9, "a block")]:
        command(f"normal! zR{lnum}G")
        send("Tab")
        check_value(f"TAB folds {name}", f"foldclosed({lnum})", str(lnum))
        send("Tab")
        check_value(f"TAB opens {name}", f"foldclosed({lnum})", "-1")
    check_value("TAB off a heading raises no error", "execute('messages') =~# 'E[0-9]\\+:'", "0")
    # It's also Ctrl-i, so after Ctrl-o it goes forward again.
    command("normal! zRgg")
    command("call cursor(7, 1)")
    send("G")
    send("C-o")
    check_value("Ctrl-o goes back", "line('.')", "7")
    send("Tab")
    check_value("TAB jumps forward", "line('.')", "14")


def test_concealing():
    start(str(home / "doc.org"))
    command("normal! zRgg")
    expect("markers hidden off the cursor line", r"bold and italic and a link and jump")
    command("call search('bold')")
    expect("real text on the cursor line", r"\*bold\* and /italic/ and \[\[https://example.com\]\[a link\]\]")


def test_which_key():
    start(str(home / "doc.org"))
    send("Space")
    expect_gone("no popup before the delay", r"\+buffer")
    expect("popup appears after the delay", r"\+buffer", 2)
    expect("the top level lists find file", r"SPC → Find file in project")
    expect("org keys appear in an org file", r"m → \+org local")
    send("m")
    expect("next level", r"t → \+todo")
    expect("breadcrumb", r"SPC m")
    send("BSpace")
    expect("backspace goes up", r"\+buffer")
    send("Escape")
    expect_gone("Esc closes it", r"\+buffer")
    send("Space", "z")
    expect("an unknown key says so", r"SPC z is undefined")
    # Outside org the org menu isn't offered.
    start(str(home / "git/proj-alpha/README.md"))
    send("Space")
    expect("menu in other files", r"\+buffer", 2)
    check("no org menu in other files", "org local" not in screen(), "org local shown")
    send("Escape")
    # Visual mode keeps its selection through the menu.
    send("v")
    send("Space")
    expect("menu in Visual mode", r"\+buffer", 2)
    send("Escape")
    expect("still in Visual mode", r"-- VISUAL --")
    send("Escape")


def test_fast_typing_and_projects():
    start(str(home / "doc.org"))
    # All of this arrives at once, faster than anything can draw. If a key leaked to
    # Vim, `a` would start Insert mode and the rest would land in the buffer.
    send("Space", "p", "p")
    type_text("alpha")
    expect("project picker filtered", r"proj-alpha")
    expect("nothing leaked", r"^.*> alpha")
    send("Enter")
    expect("find-file follows", r"Find file: ~/git/proj-alpha")
    type_text("needle")
    expect("file filtered", r"src/needle\.txt")
    send("Enter")
    expect("file opened", r"the haystack line")
    check_value("right file", "expand('%:t')", "'needle.txt'")
    check_value("working directory changed", "getcwd()", repr(str(home / "git/proj-alpha")))
    check_value("buffer unmodified", "&modified", "0")
    # The earlier project is first the next time, and SPC SPC uses the current project.
    send("Space", "p", "p")
    expect("recent project first", r"> .*\n.*proj-alpha")
    send("Escape")
    send("Space", "Space")
    type_text("READ")
    expect("SPC SPC finds in project", r"README\.md")
    send("Enter")
    expect("README opened", r"# alpha")
    # Other buffers stay open across a project switch.
    send("Space", "b", "b")
    expect("buffer switcher", r"Switch buffer")
    expect("lists the earlier files", r"needle\.txt")
    send("Escape")


def test_project_search():
    start(str(home / "git/proj-alpha/README.md"))
    send("Space", "s", "p")
    type_text("haystack")
    expect("search results", r"src/needle\.txt:2: the haystack line")
    send("Enter")
    expect("opens the match", r"the haystack line")
    check_value("on the matching line", "line('.')", "2")
    check_value("at the match", "col('.')", "5")
    # A new search while one is showing replaces the results.
    send("Space", "s", "p")
    type_text("first")
    expect("second search", r"needle\.txt:1: first")
    send("C-u")
    type_text("nothingmatchesthisatall")
    expect_gone("results clear", r"needle\.txt:1")
    send("C-u")
    type_text("alpha")
    expect("third search", r"README\.md:1: # alpha")
    send("C-q")
    expect("C-q fills quickfix", r"Quickfix List")


def test_capture():
    start(str(home / "doc.org"))
    work = home / "git/private-work/todo.org"
    work.write_text("* Todo list\n** TODO Old\n* After\n")
    send("Space", "X")
    expect("capture menu", r"w → \+Work")
    send("w")
    expect("capture group", r"t → Work Todo - today")
    send("t")
    expect("capture prompt", r"Work Todo - today:")
    type_text("Real capture")
    send("Enter")
    expect("capture confirms", r"Captured to")
    expect_file("capture reaches the file", work, "* Todo list\n** TODO Real capture \n SCHEDULED: <2026-11-11 Wed>\n** TODO Old\n")
    check_value("still in the same file", "expand('%:t')", "'doc.org'")
    # Esc at the prompt writes nothing.
    send("Space", "X", "w", "w")
    expect("prompt", r"Work Todo:")
    type_text("Abandoned")
    send("Escape")
    time.sleep(0.2)
    check("Esc cancels", "Abandoned" not in work.read_text(), work.read_text())
    # Fast typing all the way through.
    send("Space", "X", "c", "T")
    type_text("Client thing")
    send("Enter")
    expect_file("fast capture", home / "git/private-client/notes.org", "** TODO Client thing \n SCHEDULED: <2026-11-12 Thu>\n")


def test_agenda():
    start(str(home / "doc.org"))
    (home / "git/private-work/todo.org").write_text(
        "#+FILETAGS: :work:\n* Todo list\n** TODO Act on this\nSCHEDULED: <2026-11-11 Wed>\n** TODO [#A] Urgent\n"
    )
    send("Space", "o", "A")
    expect("agenda menu", r"w → Work agenda view")
    send("w")
    expect("work view", r"High priority unfinished tasks")
    expect("the item shows", r"Urgent")
    check_value("agenda filetype", "&filetype", "'orgagenda'")
    # Ordinary Vim works: search with / must not trigger the agenda keys.
    send("/")
    type_text("Act on")
    send("Enter")
    check_value("search found it", "getline('.') =~# 'Act on this'", "1")
    # A real pick from the TODO menu.
    send("t")
    expect("todo menu", r"d → DONE")
    send("d")
    expect_file("t changes the file", home / "git/private-work/todo.org", "** DONE Act on this")
    expect("agenda refreshed", r"Today's completed tasks")
    expect("item moved blocks", r"todo:\s+DONE Act on this")
    # Priority and refresh.
    send("g", "g")
    send("/")
    type_text("Urgent")
    send("Enter")
    send("J")
    expect_file("J lowers priority", home / "git/private-work/todo.org", "** TODO [#B] Urgent")
    (home / "git/private-work/todo.org").write_text("#+FILETAGS: :work:\n* Todo list\n** TODO Fresh from outside\n")
    send("r")
    expect("r refreshes", r"Fresh from outside")
    send("g", "r")
    expect("gr refreshes too", r"Fresh from outside")
    # SPC menu inside the agenda.
    send("/")
    type_text("Fresh")
    send("Enter")
    send("Space", "m", "t", "W")
    expect_file("SPC m t W sets WAIT from the agenda", home / "git/private-work/todo.org", "** WAIT Fresh from outside")
    send("q")
    expect("q returns", r"\* Second …")
    # The simple view has the week, and [[ moves it.
    (home / "git/private-work/todo.org").write_text("* TODO Dated\nSCHEDULED: <2026-11-11 Wed>\n")
    send("Space", "o", "A", "c")
    expect("week view", r"Week-agenda \(W46\)")
    send("]", "]")
    expect("next week", r"Week-agenda \(W47\)")
    send("[", "[")
    expect("back", r"Week-agenda \(W46\)")
    send("/")
    type_text("Scheduled:  TODO Dated")
    send("Enter")
    send("L")
    expect_file("L moves the date", home / "git/private-work/todo.org", "SCHEDULED: <2026-11-12 Thu>")
    send("g", "g")
    send("/")
    type_text("TODO Dated")
    send("Enter")
    send("Enter")
    expect("Enter opens the item", r"^\* TODO Dated")
    check_value("in the real file", "expand('%:t')", "'todo.org'")


def test_org_commands():
    path = home / "edit.org"
    path.write_text("* Alpha :x:\nalpha body\n* Beta\n** Kid\n* Gamma\n[[*Alpha]]\n|a|b|\n|cc|dd|\n")
    start(str(path))
    command("normal! zRgg")
    send("Space", "m", "t", "p")
    expect("SPC m t p", r"IN PROGRESS Alpha")
    send("Space", "m", "s", "t")
    expect("SPC m s t", r"SCHEDULED: <2026-11-11 Wed>")
    send("Space", "m", "t", "m")
    expect("picker lists all keywords", r"LOOP")
    send("Escape")
    send("Space", "w")
    expect_file("SPC w saves", path, "* IN PROGRESS Alpha :x:\nSCHEDULED: <2026-11-11 Wed>\n")
    # Alt keys arrive as ESC+key in a terminal.
    send("M-j")
    expect("M-j moves the subtree", r"(?s)Beta.*IN PROGRESS Alpha")
    check_value("the move is right", "getline(1)", "'* Beta'")
    send("M-k")
    check_value("M-k moves it back", "getline(1) =~# 'Alpha'", "1")
    send("M-l")
    check_value("M-l demotes", "getline(1)[0:1]", "'**'")
    send("M-h")
    check_value("M-h promotes", "getline(1)[0:1]", "'* '")
    command("call cursor(4, 1)")
    send("M-L")
    check_value("M-L demotes the subtree", "getline(4, 5)", "['** Beta', '*** Kid']")
    send("M-H")
    check_value("M-H promotes it", "getline(4, 5)", "['* Beta', '** Kid']")
    # A quick Esc then j isn't Alt+j: Vim is already waiting for the next key, so a gap
    # as small as a human's makes these two separate keys.
    command("call cursor(1, 1)")
    send("Escape")
    time.sleep(0.1)
    send("j")
    check_value("Esc then j is just j", "line('.')", "2")
    # Table TAB in Normal mode and Insert mode.
    command("call search('^|a')")
    send("Tab")
    check_value("TAB aligns the table", "getline('.')", "'| a  | b  |'")
    send("i")
    send("Tab")
    type_text("X")
    send("Escape")
    check_value("Insert TAB moves to the next cell", "getline('.')", "'| a  | Xb  |'")
    send("u")
    # Insert TAB elsewhere is a real tab, and new headings don't fold around the cursor.
    command("call cursor(line('$'), 1)")
    send("o")
    type_text("* Brand new heading")
    send("Enter")
    type_text("under it")
    send("Escape")
    expect("typed text stays visible", r"under it")
    check_value("heading fold open", "foldclosed(line('.'))", "-1")
    check_value("folding restored", "&foldmethod", "'expr'")
    # Enter follows an internal link and is plain Enter elsewhere.
    command("call search('\\[\\[\\*Alpha')")
    send("l", "l", "l")
    send("Enter")
    check_value("Enter follows the link", "getline('.') =~# 'Alpha'", "1")
    command("call cursor(2, 1)")
    send("Enter")
    check_value("Enter moves down off a link", "line('.')", "3")
    command("set nomodified")


def test_journal():
    start(str(home / "doc.org"))
    send("Space", "n", "j", "j")
    journal = home / "git/journal/Nov-2026.org"
    expect_file("creates the month file", journal, "* Wed 11 Nov 2026\n:PROPERTIES:\n:CREATED:  20261111\n:END:\n** 10:30 \n")
    expect("opens it", r"\*\* 10:30|\* 10:30")
    check_value("on the new entry", "getline('.')", "'** 10:30 '")
    check_value("in the journal", "expand('%:t')", "'Nov-2026.org'")
    send("A")
    type_text("wrote something")
    send("Escape")
    send("Space", "w")
    expect_file("entry saves", journal, "** 10:30 wrote something\n")


def test_navigation_others():
    start(str(home / "doc.org"))
    command("normal! zR")
    send("Space", "s", "s")
    type_text("child body")
    expect("search buffer", r"child body")
    send("Enter")
    check_value("jumps to the line", "getline('.')", "'child body'")
    send("Space", "s", "o")
    type_text("second")
    expect("search headings", r"\* Second")
    send("Enter")
    check_value("jumps to the heading", "getline('.')", "'* Second'")
    send("Space", "f", "f")
    expect("find file prompt", r"Find file: " + re.escape(str(home)))
    send("C-u")
    type_text(str(home / "git/proj-beta/beta-file.txt"))
    send("Enter")
    expect("opened the file", r"^beta$")
    send("Space", "b", "k")
    check_value("kill goes back", "expand('%:t')", "'doc.org'")
    check_value("kill wiped the buffer", "buflisted(bufnr('beta-file.txt'))", "0")


def test_fugitive_package():
    send("Escape")
    start(str(home / "doc.org"))
    send("Space", "g", "g")
    expect("explains when fugitive is missing", r"vim-fugitive isn't installed")
    # A native package install, with a stand-in for fugitive's :Git.
    stand_in = home / ".vim/pack/plugins/start/fugitive/plugin"
    stand_in.mkdir(parents=True)
    (stand_in / "fugitive.vim").write_text('command! Git echo "git status from package"\n')
    start(str(home / "doc.org"))
    send("Space", "g", "g")
    expect("SPC g g runs :Git from a native package", r"git status from package")


def test_shared_settings():
    """The real settings.json mechanism: Vim reads what VS Code reads."""
    settings = home / "shared.json"
    settings.write_text('{\n  // from VS Code\n  "orgflow.journal.directory": "~/elsewhere",\n}\n')
    (home / "vimrc-extra.vim").write_text(f"let g:orgflow_settings_file = '{settings}'\n")
    start("--cmd", f"source {home}/vimrc-extra.vim", str(home / "doc.org"))
    send("Space", "n", "j", "j")
    expect_file("journal directory from settings.json", home / "elsewhere/Nov-2026.org", "** 10:30 ")


TESTS = [
    test_startup,
    test_folding_keys,
    test_tab_off_a_heading,
    test_concealing,
    test_which_key,
    test_fast_typing_and_projects,
    test_project_search,
    test_capture,
    test_agenda,
    test_org_commands,
    test_journal,
    test_navigation_others,
    test_fugitive_package,
    test_shared_settings,
]


def main():
    build_home()
    try:
        for test in TESTS:
            if len(sys.argv) > 1 and test.__name__ not in sys.argv[1:]:
                continue
            before = len(failures)
            test()
            print(f"{test.__name__}: {'ok' if len(failures) == before else 'FAILED'}", flush=True)
            for failure in failures[before:]:
                print(failure, flush=True)
    finally:
        tmux("kill-server")
        shutil.rmtree(home, ignore_errors=True)
    print(f"{passed} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
