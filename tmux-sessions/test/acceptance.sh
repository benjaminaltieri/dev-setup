#!/usr/bin/env bash
# Acceptance tests for tmux-snap / tmux-restore (spec section 5.5).
#
# Runs entirely on a dedicated tmux socket so a live byobu session is never
# touched. Creates three real, resumable Claude Code sessions.
#
#   ./test/acceptance.sh            # all tests
#   ./test/acceptance.sh --keep     # leave the test server up for inspection
#
# Two things learned the hard way, both encoded below:
#  * Claude Code writes ~/.claude/sessions/<pid>.json only on the FIRST USER
#    PROMPT, not at startup. Tests that need the session-file discovery path must
#    send a prompt first.
#  * A tmux client attached through `script` must keep stdin open, or the EOF
#    reaches the pane's shell, the shell exits, and the whole server dies.

set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SNAP="$HERE/bin/tmux-snap"
RESTORE="$HERE/bin/tmux-restore"

SOCK="${ACC_SOCK:-/tmp/tmux-acctest.sock}"
BASE="${ACC_BASE:-/tmp/tmux-acctest}"
SNAPDIR="$BASE/snapdir"
KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

CLAUDE="$HOME/.local/bin/claude"

PASS=0; FAIL=0
ok()    { printf '  \033[32mPASS\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()   { printf '  \033[31mFAIL\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
head_() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
eq()    { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1: want [$3] got [$2]"; fi; }

tm() { tmux -S "$SOCK" "$@"; }

agents_seen() {
  "$SNAP" -S "$SOCK" --stdout --no-annotate 2>/dev/null \
    | jq '[.sessions[].windows[].panes[] | select(.claude != null)] | length' 2>/dev/null
}

# Attach a headless client. stdin is held open by a sleep so its EOF never
# reaches the pane's shell.
ATTACH_SLEEP=600
attach_client() {
  sleep "$ATTACH_SLEEP" | script -q /dev/null tmux -S "$SOCK" attach -t acc >/dev/null 2>&1 &
  sleep 3
}
detach_client() { pkill -f "tmux -S $SOCK attach" 2>/dev/null; }

# Type a prompt into an agent pane and submit it (the TUI needs Enter separately).
prompt_pane() {
  tm send-keys -t "$1" "$2"; sleep 1; tm send-keys -t "$1" Enter
}

wait_for() { # wait_for <seconds> <shell-test>
  local n="$1"; shift
  local i
  for i in $(seq 1 "$n"); do
    if eval "$@"; then return 0; fi
    printf '.'; sleep 1
  done
  return 1
}

# Wait for the Claude Code TUI to actually be accepting input. #{pane_current_command}
# is useless for this: it reports "node", a version string, or whatever child
# process happens to be in the foreground, so it can look "not a shell" seconds
# before the prompt box exists. Typing early means the prompt is swallowed and
# the session never registers.
wait_tui() { # wait_tui <target> [seconds]
  local t="$1" n="${2:-90}" i
  for i in $(seq 1 "$n"); do
    if tm capture-pane -p -t "$t" 2>/dev/null | grep -q '❯'; then return 0; fi
    printf '.'; sleep 1
  done
  return 1
}

cleanup() {
  detach_client
  if [ "$KEEP" -eq 0 ]; then
    tm kill-server 2>/dev/null
    rm -rf "$BASE"
  else
    printf '\n(--keep) test server left on %s\n' "$SOCK"
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
head_ "setup: three real resumable Claude sessions"
tm kill-server 2>/dev/null
rm -rf "$BASE"; mkdir -p "$SNAPDIR" "$BASE/alpha" "$BASE/beta" "$BASE/gamma"

for pair in alpha:ELDERBERRY beta:MARMALADE gamma:ZEPPELIN; do
  d="${pair%%:*}"; word="${pair##*:}"
  uuid="$(uuidgen | tr 'A-Z' 'a-z')"
  printf '%s' "$uuid" > "$BASE/$d.uuid"
  ( cd "$BASE/$d" && "$CLAUDE" --session-id "$uuid" -n "acc-$d" \
      -p "Reply with exactly OK. Remember the codeword $word." \
      >"$BASE/$d.create.log" 2>&1 </dev/null )
  if grep -qi 'ok' "$BASE/$d.create.log"; then
    printf '  created acc-%s = %s (codeword %s)\n' "$d" "$uuid" "$word"
  else
    printf '  WARN acc-%s create output: %s\n' "$d" "$(tail -2 "$BASE/$d.create.log")"
  fi
done

A_UUID="$(cat "$BASE/alpha.uuid")"
B_UUID="$(cat "$BASE/beta.uuid")"
G_UUID="$(cat "$BASE/gamma.uuid")"

# ---------------------------------------------------------------------------
head_ "build layout: 3 windows, one with 4 panes non-uniform, 3 agent panes"
tm new-session -d -s acc -n win-one -c "$BASE/alpha" -x 200 -y 50
tm new-window -d -t acc:1 -n win-four -c "$BASE/beta"
tm split-window -d -t acc:1 -c "$BASE/beta"
tm split-window -d -t acc:1 -c "$BASE/gamma"
tm split-window -d -t acc:1 -c "$BASE/gamma"
tm select-layout -t acc:1 tiled
tm resize-pane -t acc:1.0 -x 120
tm resize-pane -t acc:1.2 -y 12
tm new-window -d -t acc:2 -n win-plain -c "$HOME"

attach_client
eq "headless client attached" "$(tm list-clients -F x 2>/dev/null | grep -c x)" "1"

# acc:0.0 and acc:1.0 get pane options only  -> exercises the pane-option path
# acc:1.2 gets a prompt (no pane options)    -> exercises the session-file path
tm send-keys -t acc:0.0 "cd $BASE/alpha && $CLAUDE --resume $A_UUID -n acc-alpha" Enter
tm set-option -p -t acc:0.0 @cc_sid  "$A_UUID"
tm set-option -p -t acc:0.0 @cc_name "acc-alpha"

tm send-keys -t acc:1.0 "cd $BASE/beta && $CLAUDE --resume $B_UUID -n acc-beta" Enter
tm set-option -p -t acc:1.0 @cc_sid  "$B_UUID"
tm set-option -p -t acc:1.0 @cc_name "acc-beta"

tm send-keys -t acc:1.2 "cd $BASE/gamma && $CLAUDE --resume $G_UUID -n acc-gamma" Enter

printf '  waiting for the three agent TUIs'
wait_tui acc:0.0 120; wait_tui acc:1.0 120; wait_tui acc:1.2 120
printf '\n'

# Force acc:1.2 to register its session file (Claude Code writes it on the first
# user prompt, never at startup).
prompt_pane acc:1.2 "Reply with exactly READY."
printf '  waiting for session-file registration'
wait_for 90 '[ "$(agents_seen)" -ge 3 ]'
printf ' got %s\n' "$(agents_seen)"

eq "3 agents bound to panes before snapshot" "$(agents_seen)" "3"

PROV="$("$SNAP" -S "$SOCK" --stdout --no-annotate \
        | jq -r '[.sessions[].windows[].panes[] | select(.claude!=null) | .claude.source] | sort | join(",")')"
case "$PROV" in
  *pane-option*session-file*|*session-file*pane-option*) ok "both discovery paths exercised ($PROV)" ;;
  *) bad "expected both discovery sources, got [$PROV]" ;;
esac

# ---------------------------------------------------------------------------
head_ "TEST 1: round trip (layout, panes, cwds, live agents)"

L0_BEFORE="$(tm display-message -p -t acc:0 '#{window_layout}')"
L1_BEFORE="$(tm display-message -p -t acc:1 '#{window_layout}')"
L2_BEFORE="$(tm display-message -p -t acc:2 '#{window_layout}')"
CWD_BEFORE="$(tm list-panes -a -F '#{window_index}.#{pane_index} #{pane_current_path}' | sort)"
SID_BEFORE="$("$SNAP" -S "$SOCK" --stdout --no-annotate \
              | jq -S '[.sessions[].windows[].panes[].claude.session_id | select(.!=null)] | sort')"

"$SNAP" -S "$SOCK" -o "$SNAPDIR"
SNAPFILE="$SNAPDIR/latest.json"
if [ -L "$SNAPFILE" ]; then ok "latest.json symlink written"; else bad "latest.json symlink missing"; fi

detach_client
tm kill-server 2>/dev/null
sleep 1
if tmux -S "$SOCK" list-sessions >/dev/null 2>&1; then
  bad "server should be dead after kill-server"
else
  ok "server killed (simulated reboot)"
fi

# Restore from a plain shell with no TMUX; socket comes from the snapshot alone.
( unset TMUX; "$RESTORE" -f "$SNAPFILE" ) 2>&1 | sed 's/^/    /'

printf '  waiting for restored agent TUIs'
wait_tui acc:0.0 120; wait_tui acc:1.0 120; wait_tui acc:1.2 120
printf '\n  waiting for plain panes to process their cd'
wait_for 30 '[ "$(tm list-panes -a -F "#{window_index}.#{pane_index} #{pane_current_path}" | sort)" = "$CWD_BEFORE" ]'
printf '\n'

eq "window count"        "$(tm list-windows -t acc -F x | grep -c x)" "3"
eq "win 0 pane count"    "$(tm list-panes -t acc:0 -F x | grep -c x)" "1"
eq "win 1 pane count"    "$(tm list-panes -t acc:1 -F x | grep -c x)" "4"
eq "win 2 pane count"    "$(tm list-panes -t acc:2 -F x | grep -c x)" "1"
eq "win 0 layout string" "$(tm display-message -p -t acc:0 '#{window_layout}')" "$L0_BEFORE"
eq "win 1 layout string" "$(tm display-message -p -t acc:1 '#{window_layout}')" "$L1_BEFORE"
eq "win 2 layout string" "$(tm display-message -p -t acc:2 '#{window_layout}')" "$L2_BEFORE"
eq "window names"        "$(tm list-windows -t acc -F '#{window_name}' | tr '\n' ',')" "win-one,win-four,win-plain,"
eq "cwd per pane"        "$(tm list-panes -a -F '#{window_index}.#{pane_index} #{pane_current_path}' | sort)" "$CWD_BEFORE"

for t in 0.0 1.0 1.2; do
  if tm capture-pane -p -t "acc:$t" | grep -q '❯'; then
    ok "pane $t has a live agent TUI"
  else
    bad "pane $t has no agent TUI"
  fi
done

# No prompts have been sent since restore, so no session files exist yet: this
# only passes because of the @cc_sid pane-option fallback.
N_FB="$(agents_seen)"
eq "agents still discoverable with zero session files (fallback)" "$N_FB" "3"
SID_AFTER="$("$SNAP" -S "$SOCK" --stdout --no-annotate \
             | jq -S '[.sessions[].windows[].panes[].claude.session_id | select(.!=null)] | sort')"
eq "same session ids resumed (not new ones)" "$SID_AFTER" "$SID_BEFORE"

# ---------------------------------------------------------------------------
head_ "TEST 2: conversation continuity in a restored pane"
attach_client
prompt_pane acc:1.2 "What codeword did I ask you to remember? Reply with just the word."
printf '  waiting for the answer'
FOUND=0
for i in $(seq 1 45); do
  out="$(tm capture-pane -p -t acc:1.2 -S -300 2>/dev/null)"
  case "$out" in *ZEPPELIN*) FOUND=1; break ;; esac
  printf '.'; sleep 2
done
printf '\n'
if [ "$FOUND" -eq 1 ]; then
  ok "restored agent answered from pre-reboot history (ZEPPELIN)"
else
  bad "restored agent did not recall the codeword"
  tm capture-pane -p -t acc:1.2 -S -40 | grep -vE '^[[:space:]]*$' | tail -20 | sed 's/^/      /'
fi

# ---------------------------------------------------------------------------
head_ "TEST 3: idempotency (restore twice)"
W_1="$(tm list-windows -t acc -F x | grep -c x)"
P_1="$(tm list-panes -a -F x | grep -c x)"
( unset TMUX; "$RESTORE" -f "$SNAPFILE" ) >/dev/null 2>&1
( unset TMUX; "$RESTORE" -f "$SNAPFILE" ) >/dev/null 2>&1
eq "window count unchanged by 2 extra restores" "$(tm list-windows -t acc -F x | grep -c x)" "$W_1"
eq "pane count unchanged by 2 extra restores"   "$(tm list-panes -a -F x | grep -c x)"      "$P_1"

BUSY="$( ( unset TMUX; "$RESTORE" -f "$SNAPFILE" ) 2>&1 | grep -c 'busy' )"
if [ "$BUSY" -ge 3 ]; then
  ok "busy agent panes are skipped, not re-driven ($BUSY skips)"
else
  bad "expected >=3 busy skips, got $BUSY"
fi

# ---------------------------------------------------------------------------
head_ "TEST 4: fresh name never opens the interactive picker"
STUB="$BASE/stub"; mkdir -p "$STUB"
cat > "$STUB/claude" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$STUB_OUT"
EOF
chmod +x "$STUB/claude"

OUT4="$(STUB_OUT="$BASE/argv1.txt" CLDS_REGISTRY="$BASE/reg" PATH="$STUB:$PATH" \
  zsh -c 'source '"$HERE"'/shell/clds.zsh; clds brand-new-name >/dev/null 2>&1; cat "$STUB_OUT"')"
case "$OUT4" in
  *--session-id*) ok "fresh name uses --session-id (no picker): $OUT4" ;;
  *--resume*)     bad "fresh name used --resume (would open a picker): $OUT4" ;;
  *)              bad "unexpected argv: $OUT4" ;;
esac

OUT4B="$(STUB_OUT="$BASE/argv2.txt" CLDS_REGISTRY="$BASE/reg" PATH="$STUB:$PATH" \
  zsh -c 'source '"$HERE"'/shell/clds.zsh; clds brand-new-name >/dev/null 2>&1; cat "$STUB_OUT"')"
case "$OUT4B" in
  *--resume*) ok "second call resumes by uuid: $OUT4B" ;;
  *)          bad "second call should resume by uuid: $OUT4B" ;;
esac

REG_UUID="$(cat "$BASE/reg/brand-new-name" 2>/dev/null)"
case "$REG_UUID" in
  [0-9a-f]*-[0-9a-f]*-[0-9a-f]*-[0-9a-f]*-[0-9a-f]*) ok "registry holds a lowercase uuid ($REG_UUID)" ;;
  *) bad "registry uuid looks wrong: [$REG_UUID]" ;;
esac

# ---------------------------------------------------------------------------
head_ "TEST 5: socket handling"
eq "snapshot recorded its own socket" "$(jq -r .socket "$SNAPFILE")" "$SOCK"

DEFAULT_BEFORE="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | tr '\n' ',')"
( unset TMUX; "$RESTORE" -f "$SNAPFILE" ) >/dev/null 2>&1
DEFAULT_AFTER="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | sort | tr '\n' ',')"
eq "no stray session on the default socket" "$DEFAULT_AFTER" "$DEFAULT_BEFORE"
if tm has-session -t acc 2>/dev/null; then
  ok "restore landed on the recorded socket ($SOCK)"
else
  bad "restore did not land on the recorded socket"
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m== summary\033[0m\n'
printf '  passed: %s\n  failed: %s\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
