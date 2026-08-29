# tmux session persistence + Claude Code session launchers

Survives a reboot with the tmux layout intact and each Claude Code conversation
resumed in the pane it belonged to, plus the `cld*` launchers for starting and
resuming named sessions.

## Install

```bash
./install.sh          # idempotent; backs up anything it replaces
./install.sh --uninstall
```

That links the three commands into `~/.local/bin`, appends the `cld.zsh` source
line to `~/.zshrc`, installs the byobu key bindings, and loads a launchd timer
that snapshots every five minutes.

## What you get

| Command | |
|---|---|
| `C-a C-s` / `tmux-snap` | snapshot the layout and the session in each pane |
| `C-a C-r` / `tmux-restore` | rebuild the layout and resume every agent |
| `tmux-restore --dry-run` | preview a restore, change nothing |
| `clds <name>` | resume the session titled `<name>`, or start it |
| `cldp <file>` | same, but the title comes from a prompt file, opened with `@<file>` |
| `cldn` / `cldo` / `cldf` | `cldp` on sonnet / opus / fable |
| `cld-spawn <file>` | hand a prompt file to a new session in a split or window |

`cld`, `cldcon`, `cldres` and `cldfork` are plain aliases and live in
`../shell_aliases.sh`.

## After a reboot

Snapshot before you go (`C-a C-s`; the timer also runs every five minutes), then
**start byobu before restoring**, and press `C-a C-r`.

The ordering matters: tmux only reads byobu's `-f` profile when it *starts* the
server, so restoring first brings the server up without the status bar and with
the prefix reverted to `C-b`, which also breaks `C-a C-r` itself.

## Things that will bite you

- **Never restore onto a server where those agents are still running.** Two
  processes resuming one session id both append to the same transcript and the
  conversations interleave. A snapshot is for restoring where the agents are gone.
- **Untargeted tmux commands act on the globally active pane**, not the calling
  one, even with `$TMUX_PANE` set. An unanchored `split-window` lands in whatever
  window you are looking at; `set-option -p` stamps the pane you are viewing.
  Anchor everything with `-t "$TMUX_PANE"`.
- **`select-layout` is window-scoped**, never a subtree. Running it in a window
  that also holds your own pane reflows everything. Use per-pane `resize-pane`
  there.
- **Claude Code writes `~/.claude/sessions/<pid>.json` on the first user prompt**,
  not at startup, and its recorded pane goes stale if the pane moves between
  windows. Both are handled, but they explain why the pane options exist.
- **In zsh, `local path=` blanks out `PATH`** for the whole call, and completion
  widgets must not call `emulate -L zsh`.
- **Prompt files differing only by their ordinal prefix collide** into one title
  (`01-plan.md` and `02-plan.md` both give `plan`), and `cldp` will resume the
  first rather than start the second.

## Tests

```bash
./test/cld.sh          # fast, stubbed claude, no API calls
./test/acceptance.sh   # full round trip on an isolated socket, real sessions
```

## Layout

| Path | |
|---|---|
| `bin/tmux-snap` | snapshot layout + agent session ids to JSON |
| `bin/tmux-restore` | rebuild layout, resume agents |
| `bin/cld-spawn` | hand a prompt file to a new session |
| `shell/cld.zsh` | `clds` / `cldp` functions and completion |
| `config/byobu.tmux.conf` | key bindings, installed to `$BYOBU_CONFIG_DIR/.tmux.conf` |
| `config/*.plist` | launchd timer template (`__TMUX_SNAP__`, `__HOME__` substituted at install) |
| `~/.config/tmux-snap/` | snapshots and the `latest.json` symlink (last 40 kept) |

The design rationale, and where it departs from the original spec, is in the
Obsidian vault under `quantumscape/tmux-setup/`.
