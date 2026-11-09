# Orgflow for Vim

Org mode, agenda, journal, which-key menus and project switching for Vim 9, with a Doom One theme. It's plain Vim9script with no plugins, and reads and writes ordinary org files, so they stay compatible with Emacs and the VS Code version.

## Install

From `vim/` in the dotfiles:

```sh
./link.sh
```

That links `.vimrc` and creates a symlink in `~/.vim/pack/orgflow/start/`, which Vim loads by itself. There's no package manager or build step. To remove Orgflow, delete the symlink.

It needs Vim 9.0 or later with `+vim9script`, `+popupwin`, `+textprop`, `+conceal` and `+folding`. On any other Vim, including Neovim, it does nothing. Check with:

### Git

`SPC g g` runs fugitive's `:Git`. Fugitive installs the same way, as a native package:

```sh
mkdir -p ~/.vim/pack/plugins/start
git clone https://github.com/tpope/vim-fugitive ~/.vim/pack/plugins/start/fugitive
```

Without it, `SPC g g` says so and everything else still works.

## Settings

Vim uses the same `orgflow.*` settings as VS Code, in this order, with later ones winning:

1. `defaults.json`, a copy of the extension's defaults
2. `vscode/settings.json` in the dotfiles
3. `g:orgflow` in your `.vimrc`, for anything that should differ in Vim

So agenda files and views, capture templates, journal settings, TODO keywords and project roots only need setting once. As in VS Code, a list replaces the whole default.

```vim
let g:orgflow = {'journal.directory': '~/notes/journal', 'agenda.width': 120}
```

These only exist in Vim:

| Setting | What it does | Default |
|---|---|---|
| `g:orgflow['whichKey.delay']` | Milliseconds before the menu appears | `700` |
| `g:orgflow['vim.menu']` | Replaces the `SPC` menu (see below) | your Emacs bindings |
| `g:orgflow_settings_file` | Where to read shared settings from | `vscode/settings.json` |
| `g:orgflow_no_leader` | Don't bind `SPC`, if set before the plugin loads | not set |
| `g:orgflow_no_meta_keys` | Don't set up the Alt keys | not set |

A menu entry takes an Ex command, and `filetypes` limits it to those filetypes:

```vim
{'key': 't', 'name': 'Terminal', 'cmd': 'terminal'}
{'key': 'm', 'name': 'org local', 'filetypes': ['org'], 'children': [...]}
```

`orgflow.whichKey.menu` holds VS Code command names, so Vim ignores it. `orgflow.projects.openIn` doesn't apply either, because projects open in the same Vim.

## Keys

`SPC` opens the menu in Normal and Visual mode. Keys typed before it appears are simply the next keys in the sequence, so they can't reach Vim. `Backspace` goes up a level and `Esc` cancels.

| Keys | Action |
|---|---|
| `SPC SPC` | Find file in project |
| `SPC p p` | Switch project, then find file |
| `SPC s p` / `SPC s P` | Search project: live picker / into quickfix |
| `SPC s s` / `SPC s o` | Search this file / its headings |
| `SPC s n` | Clear search highlights |
| `SPC b b` / `SPC b k` | Switch buffer / close it |
| `SPC f f` / `SPC f r` / `SPC f s` / `SPC w` | Open file / recent files / save / save |
| `SPC g g` | Git status (fugitive) |
| `SPC X` | Capture: `t`, `p`, `w w`/`t`/`T`, `c c`/`t`/`T` |
| `SPC o A` | Agenda: `c`, `w`, `p` |
| `SPC n j j` | New journal entry |
| `SPC v v` / `SPC s v` | Edit / reload `.vimrc` |

In a picker, type to filter. `Ctrl-n`/`Ctrl-p`, `Ctrl-j`/`Ctrl-k` or the arrows move, `Enter` opens, `Ctrl-u` clears and `Esc` cancels. In `SPC s p`, `Ctrl-q` sends the results to quickfix.

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
| `TAB` | Cycle this subtree, align a table and go to the next cell, or jump forward as usual elsewhere |
| `TAB` in Insert mode | Next table cell, add a star on a heading, or an ordinary tab elsewhere |
| `S-TAB` in Insert mode | Remove a star on a heading |
| `>>` / `<<`, and `>` / `<` with a motion or in Visual mode | Add / remove a star on each heading, if the range starts on one or the cursor is on one. Elsewhere they indent as usual |
| `S-TAB` | Cycle overview, contents, show all |
| `M-j` / `M-k` | Move subtree down / up (or drag the line, off a heading) |
| `M-h` / `M-l` | Promote / demote this heading |
| `M-H` / `M-L` | Promote / demote the whole subtree |
| `Enter` | Follow the link under the cursor |
| `SPC o l` / `SPC m q` / `SPC m a` | Insert link / set tags / align table |

`TAB` on a `… N lines` row opens it. Vim's own fold commands, such as `za`, work too, and `TAB` reads the real fold state each time.

In the agenda, all Vim motions, `/` and yank work as usual, along with:

| Keys | Action |
|---|---|
| `Enter` / `TAB` | Open the item / open it in a split |
| `t` | Pick a TODO state |
| `H` / `L` | Move the date a day earlier / later |
| `J` / `K` | Priority down / up |
| `[[` / `]]` | Previous / next week |
| `r` or `gr` | Refresh |
| `q` / `C` | Close / capture |

Every command is also available directly, for example `:OrgTodo WAIT`, `:OrgSchedule fri`, `:OrgAgenda w` or `:OrgCapture wt`.

## Terminal setup

- **Colours:** Doom One needs a true-colour terminal for exact colours. `.vimrc` turns that on when `$COLORTERM` says it's available. Otherwise each colour uses its nearest match from 256.
- **Alt keys:** these rely on the terminal sending Esc plus the key. On a Mac, turn on "Use Option as Meta key" in Terminal, or `macos-option-as-alt` in Ghostty.
- **Clipboard:** `"+y` needs a Vim built with `+clipboard`. Arch's `vim` package doesn't have it.

## Differences

**From VS Code**

- Project switching changes Vim's working directory instead of opening a window, and your other buffers stay open.
- Vim draws a closed fold in one flat colour, so only the content under a heading folds. Headings and keywords always keep their colours, and each closed section takes an extra `… N lines` row, so an overview is up to twice as long.
- A parent heading's body text can fold separately from its children.
- Wrapped lines indent, and the menu waits 0.7s like your Emacs one. The agenda week keys are `[[` and `]]`, and `gr` works, as in Emacs.
- `SPC s i` (symbols) doesn't exist, because Vim has no language server built in.
- A `{regex}` in an agenda match uses Vim's regex syntax, in very magic mode, not Emacs's.

**From Emacs**

- Headings stay one font size.
- Capture takes a one-line title at a prompt rather than opening a capture buffer.
- `SPC u` (universal argument) doesn't exist.
- Terminals send the same code for `TAB` and `Ctrl-i`, so `Ctrl-i` cycles folds on a heading or table line in an org file. Everywhere else it still jumps forward.

The org syntax limits, and the behaviour copied on purpose from your Emacs config, are the same as in VS Code. See `vscode/orgflow/README.md`.

## At work

This version installs no extension, but unlike the VS Code one it does start other programs:

| Program | Used for |
|---|---|
| `git` | Listing project files (`ls-files`), and search if `rg` is missing |
| `rg` | Search and non-git file listing, if installed. It falls back to `git grep`, then `grep` and `find`. |
| `open` / `xdg-open` | Following a web link in a note, only when you press `Enter` on it |

It makes no network calls and has no telemetry. It only writes to your org and journal files, plus a list of recent projects in `~/.local/state/orgflow/`.

## Tests

| Command | What it does |
|---|---|
| `test/run.sh` | The engine against the same real org output as VS Code, then buffers, folds, file safety, agenda, capture and journal in a real Vim. Needs nothing but Vim. |
| `VIM=/path/to/vim test/run.sh` | The same with another Vim, such as the one on a work machine |
| `python3 test/e2e.py` | Real keystrokes to a real Vim in tmux, using your `.vimrc` and the `link.sh` install, under a throwaway home. Needs tmux, git and rg. |

`defaults.json` is a copy of the defaults in `vscode/orgflow/package.json`. `test/run.sh` fails if the two drift apart. To regenerate it, run this from `vim/orgflow`:

```sh
node -e 'const p=require("../../vscode/orgflow/package.json").contributes.configuration.properties,o={};for(const k of Object.keys(p).sort())if(k!=="orgflow.whichKey.menu"&&k!=="orgflow.projects.openIn")o[k.replace(/^orgflow\./,"")]=p[k].default;require("fs").writeFileSync("defaults.json",JSON.stringify(o,null,2)+"\n")'
```
