# Orgflow

Org mode, agenda, journal, which-key menus and project switching for VS Code, with a Doom One theme. It's designed to work with VSCodeVim, and reads and writes ordinary org files, so they stay compatible with Emacs.

## Install

From `vscode/` in the dotfiles:

```sh
./link.sh --extension
```

That links `settings.json` and `keybindings.json`, then builds and installs the extension. Reload VS Code afterwards. At work, check with IT first (see `IT-NOTE.md`), and don't work around a block.

Then set your paths in `settings.json` if they differ from the defaults: `orgflow.agenda.files`, `orgflow.capture.templates`, `orgflow.journal.directory` and `orgflow.projects.roots`.

## Keys

`SPC` opens the menu in Normal and Visual mode, and every level shows what's available. Keys typed faster than the menu appears are held and replayed, so they can't reach Vim.

| Keys | Action |
|---|---|
| `SPC SPC` | Find file in project |
| `SPC p p` | Switch project, then find file |
| `SPC s p` / `SPC s P` | Search project: quick picker / search panel |
| `SPC s s` / `SPC s o` | Search this file / its headings |
| `SPC b b` / `SPC b k` | Switch buffer / close it (there are no tabs) |
| `SPC f f` / `SPC f r` / `SPC f s` / `SPC w` | Open file / recent files / save / save |
| `SPC g g` | Magit |
| `SPC X` | Capture: `t`, `p`, `w w`/`t`/`T`, `c c`/`t`/`T` |
| `SPC o A` | Agenda: `c`, `w`, `p` |
| `SPC n j j` | New journal entry |

In an org file or the agenda:

| Keys | Action |
|---|---|
| `SPC m t t`/`p`/`w`/`W`/`d` | Set TODO, IN PROGRESS, IN REVIEW, WAIT, DONE |
| `SPC m t m` | Pick any TODO state |
| `SPC m s t`/`T`/`s` | Schedule today / tomorrow / pick a date |
| `SPC m d` | Set a deadline |

In an org file:

| Keys | Action |
|---|---|
| `TAB` | Cycle this subtree, or align a table and go to the next cell |
| `S-TAB` | Cycle overview, contents, show all |
| `M-j` / `M-k` | Move subtree down / up (or drag the line, off a heading) |
| `M-h` / `M-l` | Promote / demote this heading |
| `M-H` / `M-L` | Promote / demote the whole subtree |
| `Enter` | Follow the link under the cursor |
| `SPC o l` / `SPC m q` / `SPC m a` | Insert link / set tags / align table |

In the agenda, `j`, `k`, `/` and yank are ordinary Vim. These only apply in Normal mode, so they don't interfere with a search:

| Keys | Action |
|---|---|
| `Enter` / `TAB` | Open the item / open it beside the agenda |
| `t` | Pick a TODO state |
| `H` / `L` | Move the date a day earlier / later |
| `J` / `K` | Priority down / up |
| `[` / `]` | Previous / next week |
| `r` / `q` / `C` | Refresh / close / capture |

Your settings define the menu (`orgflow.whichKey.menu`), agenda views (`orgflow.agenda.views`), capture templates and TODO keywords.

## Known differences from Emacs

**Org appearance**

- Headings stay one font size, and wrapped lines aren't indented, because VS Code decorations can't do that reliably.
- `S-TAB` contents view only folds leaf entries: a fold covers a whole subtree, so a parent's own body text stays visible.

**Org syntax that isn't supported**

- Date ranges (`<a>--<b>`) are ignored by the agenda.
- `#+TODO:` lines in a file are ignored. Keywords come from settings.
- Table formulas aren't calculated. `#+TBLFM` lines are left alone.
- Diary sexps, habits, clocking, archiving and export aren't implemented, and neither is agenda undo, bulk marking or filtering. Unknown syntax is preserved untouched.

**Behaviour**

- The agenda keys are `[` and `]`, not `[[` and `]]`, and `r`, not `gr`, because VS Code key chords would break Vim's `gg`.
- Capture takes a one-line title in a prompt rather than opening a capture buffer.
- Setting a TODO doesn't re-align tags. Emacs would adjust the spacing before them.
- `SPC u` (universal argument) doesn't exist.
- Carrying over an item directly above today's heading doesn't leave the stray blank line org-journal does.
- If you fold with `za`, `TAB` can be one step behind until its next press, because VS Code doesn't expose fold state reliably.

## Tests

| Command | What it does |
|---|---|
| `npm test` | Unit tests, plus comparisons with real org output in `test/golden/expected` |
| `npm run test:integration` | The extension inside a real VS Code, in a throwaway profile |
| `npm run package && npm run test:e2e` | Real keystrokes to the packaged VSIX with real VSCodeVim and your real settings (Linux, needs Xvfb and xdotool) |
| `npm run golden` | Regenerates the expected output from real Emacs and org. Home machine only: the results are committed, so nothing else needs Emacs. |

`npm run assets` regenerates the theme and grammars. The VS Code test CLI exits 0 even when tests throw, so the integration and e2e scripts read their own result files.
