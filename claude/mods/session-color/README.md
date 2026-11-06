# session-color

A Claude Code mod (a plugin with a TypeScript hooks module) that keeps the session's prompt-bar color (`/color`) in step with the session's work stage. Scanning many sessions then shows where attention is needed.

## Stages

| Color | Stage | Set by |
|---|---|---|
| yellow | Needs your input: exploring, asking questions, plan not settled | Start; Haiku |
| green | Go-ahead given, building | Haiku (your go-ahead), or you |
| cyan | PR open; the whole review stage | Code (PR detected) |
| purple | Merged; validating and cleaning up | Code (merge detected) |
| orange | Close-out questions for you | Haiku |
| blue | Done and clean, or concluded | Haiku, gated by checks (PRs closed, no background agents, no leftover worktree or branch) |
| pink (flag) | Harness problem: permission refused, login expired | Code; cleared only by you |
| red (flag) | Blocked on something external | Haiku |

From cyan onward, automation only moves forward. Anything backward is your manual `/color`.

## Turning it on

It's off unless the session is started with `CC_SESSION_COLOR=on` (the spawn launcher sets this for worker sessions), or you run `/session-color on`. While it's off, every hook returns immediately.

## Commands

```
/session-color                  status: stage, color, flags, PRs, last move
/session-color on | off         turn it on or off for this session
/session-color ack              clear the pink harness flag
/session-color debug on | off   show a short notice with the reason for each move
/session-color feedback <text>  log feedback for tuning
/color <c>                      your override; `default` pauses the mod
```

## How it decides

- **At the end of each main-thread turn,** from a timer so it never delays the turn:
  - refresh the tracked PRs with `gh`;
  - make any move the code can decide;
  - otherwise make one Haiku call (`$.model.complete`, about 1.5 s and about 1,000 tokens), offered only `stay` plus the moves allowed from the current stage.
- **Haiku's instructions** are in `guide.md`, read on every call. Tune them there.
- **PRs are tracked** from PR URLs in tool output (`gh pr create`, `gh api .../pulls`, GitHub MCP tools) and from branches the session pushes (`gh pr list --head`).
- **While a PR is open,** `gh` checks it every 5 minutes, so merges done in the browser are caught. No timers run otherwise.

## Data

- **Per-session state:** `$.store`, managed by the engine under `~/.claude/plugins/store/`.
- **Logs:** `~/.claude/plugins/data/session-color/` (override with `SESSION_COLOR_DATA_DIR`):
  - `decisions-YYYY-MM-DD.jsonl`: every move and every Haiku call (input facts, answer, tokens, timing);
  - `feedback-YYYY-MM-DD.jsonl`: `/session-color feedback` notes, and every manual `/color` that overrides the mod.

  The logs contain conversation excerpts, so they stay local and out of any repo.

## Install

`dev-setup/setup.sh` does this:

```bash
claude plugin marketplace add ~/misc/dev-setup
claude plugin install session-color@dev-setup --scope user
```

The marketplace is a local folder, so Claude Code reads the mod in place. After editing it, run `/reload-plugins`. For live reloading while developing: `claude --plugin-dir ~/misc/dev-setup/claude/mods/session-color`.

Run `claude plugin validate ~/misc/dev-setup/claude/mods/session-color` after Claude Code updates. The mod API is early access and can change between releases.
