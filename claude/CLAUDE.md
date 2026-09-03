## **IMPORTANT**: NEVER use em dashes or their typewriter equivalent (two consecutive hyphens). Single hyphens for compound words are fine. Use commas, colons, semicolons, parentheses, or sentence breaks instead of dashes for pauses.

## **IMPORTANT**: ALWAYS USE UV FOR PYTHON PACKAGE AND TOOL INSTALLATION OUTSIDE OF A SOURCE CODE REPOSITORY. Such as for ad-hoc script running

## **IMPORTANT**: NEVER add emojis to GitHub Actions workflow YAML files (`.github/workflows/*.yml`, `.github/workflows/*.yaml`) or to GitHub Actions composite-action / reusable-workflow definitions. This applies even when existing step names in the same file already use emojis -- match the pattern of the change you're making (which should be plain text), not the legacy style around it. Emojis hurt searchability, render inconsistently across GitHub UI surfaces (job summaries, mobile, plain-text logs), and tend to drift over time as people copy-paste. Plain descriptive step names always.

## **IMPORTANT**: NEVER comment on GitHub PRs unless I explicitly ask. Opening PRs and pushing commits is fine; standalone `gh pr comment` is not.

## Writing Style

### Proper nouns for software tools
When referencing software tools, packages, or CLIs, preserve their original casing exactly as shown in the repo or tool (e.g., `poetry`, `uv`, not Poetry or UV). Keep kebab-case, snake_case, etc. as-is. In Markdown, use inline code formatting to make these names stand out.

Use rich Markdown formatting when appropriate -- inline code, bold, tables, headers. I like that style.

## Secrets and Sensitive Information
In general we want to treat passwords and API keys with care. It is ok to include them in conversations to avoid slowdowns but in general try to follow these guidelines:

- I ask you to retrieve credentials from 1Password (op) often, do not read these into context directly. Make sure they exist if needed, and use shell substitution when running commands to avoid leaking the secret into the chat context. if you are pulling a plain text field, not a password or credential, you can reveal that.

## Git Workflow
- When creating a new git branch, use `git cob <name>` -- my alias automatically prepends `benaltieri/` to the branch name
- Keep branches up to date by rebasing, not merging: use `git prom` (pull rebase on master/main) to avoid merge commits. If there are conflicts during the rebase, abort and ask me to manually resolve them
- Use `git comp` to checkout main and pull the latest changes in one step
- Use `git au` to stage tracked files (lazy add) instead of `git add .` -- avoids accidentally staging untracked files. Use `git add` directly only for new files you've created
- My GitHub handle is `BEA01_qss`; use `gh pr view --web` to open PRs in a browser after creating them

### Git Worktree Workflow
For working on multiple issues simultaneously without context switching:

#### Setup Worktrees
```bash
# Create worktree structure (one-time setup)
mkdir -p .trees

# Create worktree branches for parallel work
CURRENT_BRANCH=$(git branch --show-current)  # Save current branch
git cob issue-name                           # Create new branch
git checkout $CURRENT_BRANCH                 # Switch back to saved branch
git wta issue-name                           # Create worktree (alias for worktree add)
```

#### Working with Worktrees
```bash
# List all worktrees
git worktree list

# Work in a specific worktree
cd .trees/issue-name

# Each worktree is independent - make commits, run tests, etc.
```

#### Cleaning Up
```bash
# After merging or abandoning work
git wtrf issue-name              # Force remove worktree (when wtr fails)
git branch -D benaltieri/issue-name  # Force delete branch
```

## Claude Code Session Launchers (`cld*`)

Defined in `~/misc/dev-setup/shell_aliases.sh` (aliases) and
`~/misc/dev-setup/tmux-sessions/shell/cld.zsh` (functions). None pass a
permission flag, so `permissions.defaultMode` in `~/.claude/settings.json`
decides.

| Command | What it does |
|---------|--------------|
| `cld` | plain `claude` |
| `cldcon` | `--continue` |
| `cldres` | `--resume` (interactive picker) |
| `cldfork` | `--fork-session --resume` |
| `clds <name>` | resume the session titled `<name>`, or start it if there is none |
| `cldp <file>` | same, but the title is derived from a prompt file and the session opens by `@`-tagging that file |
| `cldn` / `cldo` / `cldf` | `cldp` on **sonnet** / **opus** / **fable** |

`clds` and `cldp` keep no state. They ask Claude Code whether a session title
exists (`claude -p '' --resume <name>`, a lookup that costs no API turn) and
then either resume it or create it. Session titles resolve **per project**, keyed
on the working directory, so a name only has to be unique within that repo.

`cldp` derives the title from the file name: directory and extension dropped,
plus a leading ordinal of up to three digits followed by `-`, `_` or `.`. So
`session-04-sla/01-sla-analysis.md` becomes `sla-analysis`, while
`2026-planning.md` keeps its year. On resume it does **not** re-send the tag, so
reopening never costs a turn. `-n` forces a new session instead of resuming.

**`-P <prefix>` names the workstream.** Prompt file names are often a bare ticket
id plus a terse description, which is hard to pick out of a session list or
search for later:

```bash
cldp -P my-project 01-CD-1234-a-ticket-task.md   # -> my-project-CD-1234-a-ticket-task
```

A trailing separator on the prefix is trimmed, so `-P my-project-` is the same.
`-t <title>` sets the title outright, and a prefix still applies on top of it.
Because the title is what the resume-vs-create probe looks for, adding a prefix
to a workstream that already has sessions starts new ones rather than resuming
the unprefixed sessions.

**Effort level** is not one of the aliases; pass it through as a flag. Anything
after the file path goes to `claude` verbatim:

```bash
cldo session-04-sla/01-sla-analysis.md --effort xhigh   # opus, xhigh effort
cldp 01-plan.md --effort low                            # default model, low effort
```

Valid levels: `low`, `medium`, `high`, `xhigh`, `max`.

### Handing work to a new session: `cld-spawn`

**When you (an agent) have written a prompt file and want a separate session to
act on it, use `cld-spawn` rather than a subagent or a background job.** It opens
a real interactive session in a new tmux split or window that Ben can switch to
and drive himself. This is the point of it: work handed off this way is not
trapped in a subagent transcript or a background process.

```bash
cld-spawn [options] <prompt-file>

  -d, --dir <dir>      working directory   (default: the prompt file's directory)
  -m, --model <name>   sonnet | opus | fable | haiku | id   (default: opus)
  -e, --effort <lvl>   low | medium | high | xhigh | max     (default: high)
  -t, --title <name>   session title       (default: derived from the file name)
  -P, --prefix <name>  prefix the title with a workstream name, so
                       01-CD-1234-a-task.md -P my-project becomes
                       my-project-CD-1234-a-task
  -s, --split          split the current window   (DEFAULT)
  -H, --horizontal     make that split side by side
  -V, --vertical       make that split stacked      (DEFAULT)
  -w, --window         make a new window instead
  -T, --target <pane>  split THAT pane rather than your own, so a second spawn
                       stacks under the first (use the pane id it printed)
  -S, --switch         jump to it now      (default: leave Ben where he is)
      --pane-id        print only the new pane's id, for chaining
      --dry-run        print the plan, change nothing
```

**Model and effort default to `opus` and `high`; the script pins them so you do
not have to.** This is deliberate rather than left unset: what a new session
inherits when neither flag is given follows whatever was last selected inside a
session, so it drifts and cannot be relied on. Override only when the task calls
for something else (a long mechanical pass on `-m sonnet`, `-e low` for a trivial
edit). Passing `-m ''` or `-e ''` omits the flag entirely and takes whatever
Claude Code would have chosen, which is rarely what you want.

Example, from an agent's Bash tool:

```bash
cld-spawn -d ~/QS/qs-etl docs/plans/03-retry-policy.md   # opus/high by default
# started 'retry-policy' in a split of window 4 (cve-remediation)
#   cwd:    /Users/benaltieri/QS/qs-etl
#   prompt: @docs/plans/03-retry-policy.md
#   model:  opus
#   effort: high
#   jump:   tmux select-window -t %61
```

**Spawning several.** Each run splits *your own* pane, so N spawns end up beside
you rather than grouped. To build a tidy column instead, give the group its own
window and chain each spawn onto the previous pane with `-T`, carrying the id in
one variable. `--pane-id` makes each run print only the pane id:

```bash
p=$(cld-spawn -w --pane-id plans/01-plan.md)          # its own window
p=$(cld-spawn -V -T "$p" --pane-id plans/02-api.md)   # under the first
p=$(cld-spawn -V -T "$p" --pane-id plans/03-tests.md) # under the second
tmux select-layout -t "$p" even-vertical              # equal heights
```

Without a finishing step each split halves the pane above it, so the column ends
up uneven (41/20/20 rows rather than 27/27/27).

**`select-layout` is safe there only because `-w` gave the group its own window.**
It applies to the whole WINDOW, never to a subtree, so running it in a window
that also holds your own pane reflows everything: a caller beside a three-pane
column gets flattened into a full-width stack and the side-by-side arrangement is
destroyed. When the group shares a window with you, resize each pane instead:

```bash
tmux resize-pane -t "$one" -y 28
tmux resize-pane -t "$two" -y 28
```

**Prompt files whose names differ only by the ordinal prefix collide.**
`01-plan.md` and `02-plan.md` both derive the title `plan`, and since `cldp`
resumes an existing title, the second spawn may reopen the first session and
never read its own file. Whether it creates or resumes depends on whether the
first session finished a turn before the second probed, so it is a race, not a
predictable rule. Either name the files so their stripped titles differ
(`01-api-design.md`, `02-test-strategy.md`), or pass an explicit `-t <title>`
for each spawn.

It prints where the session landed; relay that to Ben so he can switch to it.
Use `-S` only if he asked to be taken there, since it moves his focus.

**Notes and constraints**

- The spawned pane inherits the **tmux server's** environment, not the calling
  agent's, so `CLAUDECODE` and friends are unset and the new session is a normal
  top-level session, not a nested child. Verified.
- **A directory Claude Code has not seen before stops on a folder-trust prompt**,
  and the session will sit there until Ben answers it. Prefer a directory he
  already works in, and say so if you spawn into a fresh one.
- Requires being inside tmux. Outside it, `cld-spawn` prints the equivalent
  `cd ... && cldp ...` for Ben to run himself.
- The pane is labelled for `tmux-snap`, so a spawned session survives a reboot
  like any other.

### When writing tmux commands yourself

**Always target `$TMUX_PANE` explicitly.** An untargeted tmux command acts on the
*globally active* pane, not the calling one, even when `$TMUX_PANE` is set
correctly. `tmux split-window` with no `-t` lands in whatever window Ben is
looking at, and `tmux set-option -p` stamps the pane he is viewing. Both have
caused real bugs here.

```bash
tmux split-window -t "$TMUX_PANE" -c "$dir"      # correct
tmux set-option -p -t "$TMUX_PANE" @foo bar      # correct
```

## Confluence Page Formatting Guidelines

When creating or updating Confluence pages using the Atlassian MCP tools:

### No Redundant Titles
- **Do NOT include an H1 heading** (`# Page Title`) that duplicates the page title. Confluence already renders the page title inline at the top of the document. Starting content with `# Same Title` creates a redundant, ugly double-title.
- Start page content directly with the first meaningful element (blockquote, paragraph, heading at H2 level, etc.)

### Table Column Widths
- Confluence's default table layout gives all columns equal width, which causes excessive wrapping and tall rows when some columns contain significantly more text than others.
- When creating pages via the API with `contentFormat: "markdown"`, Confluence generates default equal-width tables. **After creating the page**, do an update pass using `contentFormat: "adf"` to set explicit column widths on tables where column content lengths vary significantly.
- **Sizing principle:** Allocate column width proportional to content length. Columns with short values (IDs, numbers, severity labels) should be narrow; columns with prose (rationale, notes, descriptions) should be wide.
- For tables where one column has much longer text, give that column 50-60% of the total width.
- Example width ratios for common table patterns:
  - `| # | Name | Description |` -- use roughly `[10%, 30%, 60%]`
  - `| Item | Severity | Notes |` -- use roughly `[25%, 15%, 60%]`
  - `| Flag | Default | Effect |` -- use roughly `[15%, 25%, 60%]`
- If a table has a "wide" layout (lots of columns or content), consider using `layout: "center"` with a wider total width (e.g., 1011px) instead of the default 760px

## Python Development Guidelines
- When building scripts in python from scratch, always prefer click over argparse
- for python project managed by poetry, use pyenv version to see which python is in use and pyenv local to set the version to use
- I am using a newer version of poetry. When locking, the --no-update flag is no longer available since the no update behavior is default for 2.x and above
