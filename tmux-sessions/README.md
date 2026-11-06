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
| `cldp -P <prefix> <file>` | prefix the title with a workstream name |
| `cldn` / `cldo` / `cldf` | `cldp` on sonnet / opus / fable |
| `cld-spawn <file>` | hand a prompt file to a new session in a split or window |
| `cdx-spawn <file>` | the same for a **Codex CLI** session, named over `codex app-server` |

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
- **`-P/--prefix` names the workstream.** Prompt file names are often just a
  ticket id and a terse description, which is hard to pick out of a session list
  later. `01-CD-1234-a-ticket-task.md -P my-project` gives
  `my-project-CD-1234-a-ticket-task`, which is also easier to search. A trailing
  separator on the prefix is trimmed, so `-P my-project-` behaves the same.
  Prefixing is orthogonal to where the title came from, so it applies to an
  explicit `-t/--title` as well. It also changes the title the resume-vs-create
  probe looks for, so adding a prefix to an existing workstream starts new
  sessions rather than resuming the unprefixed ones.
- **Prompt files differing only by their ordinal prefix collide** into one title
  (`01-plan.md` and `02-plan.md` both give `plan`), and `cldp` will resume the
  first rather than start the second.

## Codex sessions (`cdx-spawn`)

Same placement flags as `cld-spawn` (`-d -t -P -H -V -w -T -S --pane-id
--dry-run`), defaults `gpt-6.1-sol` / `high` (override with `-m`/`-e` or
`CDX_SPAWN_MODEL`/`CDX_SPAWN_EFFORT`). Anything after the prompt file goes to
`codex` verbatim. What differs, and why:

- **Naming never touches the TUI.** Codex has no launch option for a session
  name, and typing `/rename` into the pane proved unsafe on 0.166 (the trust
  dialog can draw over the banner with "Trust and continue" preselected, and a
  slow MCP startup leaves typed text unsubmitted). `bin/cdx-name-thread` instead
  asks a private `codex app-server` over JSON-RPC for the thread this session
  started (same cwd, first message = the kickoff, created after the spawn) and
  names it with `thread/name/set`. Typically 10 to 15 s, because the thread only
  exists once Codex submits its first message. The name survives Codex's own
  auto-titling and works with `codex resume` and `codex queue --thread`; the
  running TUI's status line does not show it.
- **The kickoff carries the name**: `Read the session brief at <path> and follow
  it. Your session name is <title>.` That makes each spawn's first message
  unique (so a stalled spawn's namer cannot claim a later spawn of the same
  brief) and tells Codex the name peers reach it by.
- **Folder trust is Ben's answer, never the script's.** Codex asks once per
  directory it has not seen (every `~/QS` repo, the first time). `cdx-spawn`
  spots the dialog on screen (reading is safe), prints `name: PENDING`, exits 0,
  and a detached namer applies the name once it is answered (up to 30 min).
- **Exit 3** means no thread appeared within `--timeout` (a login screen, a very
  slow start); a detached namer keeps trying for 30 min and reports failure in
  the tmux status line.
- **One override:** `check_for_update_on_startup=false`, because an update
  notice is a blocking menu. On 0.166 any `-c` puts Codex in "embedded mode"
  (no shared background server); accepted.
- **No resume-or-create.** Reopen with `codex resume <title>`. Names are not
  unique in Codex, so a spawn warns when the title is already taken.
- **Panes carry `@cdx_name`, never `@cc_*`**, so `tmux-snap` records them as
  plain panes and `tmux-restore` never runs `claude --resume` on a Codex name.
- **No session color.** Codex does not load Claude mods, so `cdx-spawn` sets no
  `CC_SESSION_COLOR`.

## Tests

```bash
./test/cld.sh          # fast, stubbed claude, no API calls
./test/cdx-spawn.sh    # isolated tmux socket, stubbed codex, no API calls
./test/acceptance.sh   # full round trip on an isolated socket, real sessions
```

## Layout

| Path | |
|---|---|
| `bin/tmux-snap` | snapshot layout + agent session ids to JSON |
| `bin/tmux-restore` | rebuild layout, resume agents |
| `bin/cld-spawn` | hand a prompt file to a new session |
| `bin/cdx-spawn` | hand a prompt file to a new, named Codex session |
| `bin/cdx-name-thread` | name a Codex session over `codex app-server` (used by `cdx-spawn`) |
| `shell/cld.zsh` | `clds` / `cldp` functions and completion |
| `config/byobu.tmux.conf` | key bindings, installed to `$BYOBU_CONFIG_DIR/.tmux.conf` |
| `config/*.plist` | launchd timer template (`__TMUX_SNAP__`, `__HOME__` substituted at install) |
| `~/.config/tmux-snap/` | snapshots and the `latest.json` symlink (last 40 kept) |

The design rationale, and where it departs from the original spec, is in the
Obsidian vault under `quantumscape/tmux-setup/`.
