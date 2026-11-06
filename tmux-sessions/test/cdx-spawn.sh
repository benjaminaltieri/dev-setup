#!/usr/bin/env zsh
# Tests for cdx-spawn. Runs on a dedicated tmux socket with a stub `codex`, so it
# makes no API calls and never touches the live tmux server.
#
#   ./test/cdx-spawn.sh
#
# The stub codex records its argv, can show a login screen or the 0.166 trust
# dialog, then "starts a thread" by writing a record under $CODEX_HOME/threads.
# It also records anything typed into it: cdx-spawn must never type into Codex.
# A stub cdx-name-thread (CDX_NAME_THREAD) finds that record by cwd, kickoff and
# creation time, the way the real one asks `codex app-server`, and names it in a
# private session_index.jsonl.

emulate -L zsh
setopt no_nomatch
zmodload zsh/datetime

HERE="${0:A:h:h}"
SPAWN="$HERE/bin/cdx-spawn"
B=/tmp/cdx-spawn-test
SOCK=$B/tmux.sock
PASS=0; FAIL=0

# Both return 0 explicitly: a bare (( PASS++ )) is false while PASS is 0, which
# would make `cond && ok ... || bad ...` report a pass AND a fail.
ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; (( PASS++ )); return 0 }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; (( FAIL++ )); return 0 }
hd()  { printf '\n\033[1m== %s\033[0m\n' "$1" }
has() { [[ "$2" == *"$3"* ]] && ok "$1" || bad "$1: expected to find [$3] in: $2" }
hasnt() { [[ "$2" != *"$3"* ]] && ok "$1" || bad "$1: did not expect [$3] in: $2" }

tm() { tmux -S "$SOCK" "$@" }

tm kill-server 2>/dev/null
rm -rf $B; mkdir -p $B/stub $B/home $B/work/sub $B/briefs
B="${B:A}"          # /tmp is /private/tmp on macOS; cdx-spawn reports resolved paths
SOCK=$B/tmux.sock
ARGV=$B/argv

cat > $B/stub/codex <<'EOF'
#!/bin/sh
: > "$CDX_STUB_ARGV"
cwd=""; last=""; prev=""
for a in "$@"; do
  printf '%s\n' "$a" >> "$CDX_STUB_ARGV"
  [ "$prev" = "-C" ] && cwd="$a"
  prev="$a"; last="$a"
done
if [ -n "$CDX_STUB_NOBANNER" ] && [ -f "$CDX_STUB_NOBANNER" ]; then
  echo "Sign in with ChatGPT to continue"
  exec cat >/dev/null
fi
if [ -n "$CDX_STUB_TRUST" ] && [ -f "$CDX_STUB_TRUST" ]; then
  # 0.166 can show the banner and then this dialog (the race that made typing
  # unsafe), with "Trust and continue" preselected.
  echo ">_ OpenAI Codex (v0.0.0-stub)"
  echo "Folder access"
  echo "Trust this folder? Codex can read, edit, and run files here..."
  echo "> 1. Trust and continue"
  echo "  2. Quit"
  IFS= read -r answer
  printf '%s\n' "$answer" >> "$CODEX_HOME/answered"
  clear
fi
echo ">_ OpenAI Codex (v0.0.0-stub)"
mkdir -p "$CODEX_HOME/threads"
printf '%s\n%s\n%s\n' "$cwd" "$last" "$(date +%s)" > "$CODEX_HOME/threads/stub-$$"
while IFS= read -r line; do printf '%s\n' "$line" >> "$CODEX_HOME/typed"; done
EOF
chmod +x $B/stub/codex

cat > $B/stub/cdx-name-thread <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd) cwd="$2";; --kickoff) kick="$2";; --since) since="$2";;
    --name) name="$2";; --timeout) timeout="$2";;
  esac
  shift 2
done
idx="$CODEX_HOME/session_index.jsonl"
end=$(( $(date +%s) + timeout ))
while [ "$(date +%s)" -le "$end" ]; do
  for f in "$CODEX_HOME"/threads/stub-*; do
    [ -f "$f" ] || continue
    id="${f##*/}"
    if [ "$(sed -n 1p "$f")" = "$cwd" ] && [ "$(sed -n 2p "$f")" = "$kick" ] \
       && [ "$(sed -n 3p "$f")" -ge "$since" ]; then
      printf '{"id":"%s","thread_name":"%s","updated_at":"%s"}\n' \
        "$id" "$name" "$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)" >> "$idx"
      echo "$id"; exit 0
    fi
  done
  sleep 0.2
done
exit 2
EOF
chmod +x $B/stub/cdx-name-thread

printf 'brief\n' > $B/briefs/01-brief-one.md
printf 'brief\n' > $B/work/sub/02-CD-1-thing.md
printf 'brief\n' > $B/work/03-other.md
NOBANNER=$B/nobanner   # the stub hangs on a fake login screen while this file exists
TRUSTQ=$B/trustq       # the stub asks the folder-trust question while this file exists

# The server's environment is what the spawned panes inherit, so the stub, the
# private CODEX_HOME and the argv file are set where the server starts.
env PATH="$B/stub:$PATH" CODEX_HOME=$B/home CDX_STUB_ARGV=$ARGV CDX_STUB_NOBANNER=$NOBANNER CDX_STUB_TRUST=$TRUSTQ \
  tmux -S "$SOCK" -f /dev/null new-session -d -s t -n main -x 220 -y 60 -c $B/work
# tmux starts panes as LOGIN shells, and a login profile puts ~/.local/bin (the
# real codex) ahead of the stub; a plain non-login sh with PATH pinned avoids that.
tm set-option -g default-shell /bin/sh
tm set-option -g default-command "env PATH='$B/stub:$PATH' /bin/sh"
ANCHOR="$(tm display-message -p -t t:main '#{pane_id}')"

spawn() {  # spawn <args...>; stdout+stderr in $out, status in $rc
  out="$(TMUX="$SOCK,0,0" TMUX_PANE="$ANCHOR" CODEX_HOME=$B/home CDX_NAME_THREAD=$B/stub/cdx-name-thread \
         CDX_SPAWN_BG_WAIT=20 "$SPAWN" --timeout 8 "$@" 2>&1)"
  rc=$?
}
# Drop every pane and window but the anchor, so splits never run out of room.
reset_panes() {
  tm kill-pane -a -t "$ANCHOR" 2>/dev/null
  tm list-windows -t t -F '#{window_id}' | while read -r w; do
    [[ "$w" == "$(tm display-message -p -t "$ANCHOR" '#{window_id}')" ]] || tm kill-window -t "$w"
  done
}
npanes() { tm list-panes -a | wc -l | tr -d ' ' }
argv_of() { [[ -f $ARGV ]] && tr '\n' ' ' < $ARGV }

# ------------------------------------------------------------------------------
hd "dry run: plans, creates nothing"
before=$(npanes)
spawn --dry-run -d $B/work $B/briefs/01-brief-one.md
(( rc == 0 )) && ok "exit 0" || bad "exit $rc: $out"
has  "names the cwd"              "$out" "-C $B/work"
has  "pins the model"             "$out" "-m gpt-6.1-sol"
has  "pins the effort"            "$out" "model_reasoning_effort=high"
has  "disables the update menu"   "$out" "check_for_update_on_startup=false"
hasnt "no paste-burst override (nothing is typed now)" "$out" "disable_paste_burst"
has  "plans the naming"           "$out" "name the new thread 'brief-one'"
[[ $(npanes) == $before ]] && ok "no pane created" || bad "pane count changed"

# ------------------------------------------------------------------------------
hd "split: starts codex in the right directory and names it"
before=$(npanes); rm -f $ARGV
spawn -d $B/work $B/briefs/01-brief-one.md
(( rc == 0 )) && ok "exit 0" || bad "exit $rc: $out"
has "reports the name and thread"  "$out" "name:   brief-one (thread stub-"
[[ $(npanes) == $(( before + 1 )) ]] && ok "one new pane" || bad "expected one new pane"
p1="$(print -r -- "$out" | sed -n 's/.*jump:   tmux select-window -t //p')"
[[ "$(tm display-message -p -t "$p1" '#{@cdx_name}')" == brief-one ]] && ok "pane labelled @cdx_name" || bad "missing @cdx_name on $p1"
[[ -z "$(tm display-message -p -t "$p1" '#{@cc_name}#{@cc_sid}')" ]] && ok "no @cc_* label (tmux-snap must not treat it as Claude)" || bad "pane carries @cc_* options"
[[ "$(tm display-message -p -t "$p1" '#{pane_current_path}')" == $B/work ]] && ok "pane cwd is the -d dir" || bad "pane cwd: $(tm display-message -p -t "$p1" '#{pane_current_path}')"
a="$(argv_of)"
has "codex got -C <dir>"           "$a" "-C $B/work "
has "brief outside cwd: absolute"  "$a" "Read the session brief at $B/briefs/01-brief-one.md and follow it."
has "kickoff carries the name"     "$a" "Your session name is brief-one."
[[ "$(tm display-message -p -t "$p1" '#{window_name}')" == main ]] && ok "split stays in the anchor's window" || bad "split landed elsewhere"

# ------------------------------------------------------------------------------
reset_panes
hd "default cwd, relative kickoff, ordinal stripping, prefix"
rm -f $ARGV
spawn -P ws $B/work/sub/02-CD-1-thing.md
(( rc == 0 )) && ok "exit 0" || bad "exit $rc: $out"
has "title is prefix + stripped name" "$out" "started codex 'ws-CD-1-thing'"
a="$(argv_of)"
has "cwd defaults to the file's dir"  "$a" "-C $B/work/sub "
has "brief under cwd: relative"       "$a" "Read the session brief at 02-CD-1-thing.md and follow it."

# ------------------------------------------------------------------------------
reset_panes
hd "new window, omitted model/effort, passthrough args"
rm -f $ARGV
spawn -w -m '' -e '' -t win-test $B/work/03-other.md -s workspace-write
(( rc == 0 )) && ok "exit 0" || bad "exit $rc: $out"
tm list-windows -t t -F '#{window_name}' | grep -qx win-test && ok "window named after the title" || bad "no window named win-test"
a="$(argv_of)"
hasnt "-m '' omits the model"       "$a" "-m "
hasnt "-e '' omits the effort"      "$a" "model_reasoning_effort"
has   "passthrough reaches codex"   "$a" "-s workspace-write Read the session brief"

# ------------------------------------------------------------------------------
reset_panes
hd "--pane-id prints only the id, and -T chains a stack"
spawn --pane-id -t chain-a $B/work/03-other.md
[[ "$out" == %<-> ]] && ok "printed a bare pane id ($out)" || bad "expected a pane id, got: $out"
pa="$out"
spawn --pane-id -T "$pa" -t chain-b $B/work/03-other.md
pb="$out"
[[ "$(tm display-message -p -t "$pa" '#{window_id}')" == "$(tm display-message -p -t "$pb" '#{window_id}')" ]] \
  && ok "second spawn split the first one's window" || bad "chained spawn landed in another window"

# ------------------------------------------------------------------------------
reset_panes
hd "duplicate name warns"
spawn -t brief-one $B/work/03-other.md
has "warns that resume would be ambiguous" "$out" "1 existing Codex session(s) already named 'brief-one'"

# ------------------------------------------------------------------------------
reset_panes
hd "codex never comes up: started, not named, exit 3"
touch $NOBANNER
t0=$EPOCHREALTIME
out="$(TMUX="$SOCK,0,0" TMUX_PANE="$ANCHOR" CODEX_HOME=$B/home CDX_NAME_THREAD=$B/stub/cdx-name-thread \
       CDX_SPAWN_BG_WAIT=3 "$SPAWN" --timeout 2 -t stuck $B/work/03-other.md 2>&1)"; rc=$?
rm -f $NOBANNER
(( rc == 3 )) && ok "exit 3" || bad "expected exit 3, got $rc: $out"
has "explains the wait"         "$out" "has not started its first turn after 2s"
has "shows what the pane shows" "$out" "Sign in with ChatGPT"
has "keeps trying"              "$out" "naming continues in the background"
has "summary says pending"      "$out" "name:   PENDING: codex has not started yet"
(( EPOCHREALTIME - t0 < 6 )) && ok "honours --timeout" || bad "took $(( EPOCHREALTIME - t0 ))s"

# ------------------------------------------------------------------------------
reset_panes
hd "folder-trust question: not a failure, named once answered"
touch $TRUSTQ
spawn -t trusted-later $B/work/03-other.md
rm -f $TRUSTQ
(( rc == 0 )) && ok "exit 0" || bad "expected exit 0, got $rc: $out"
has "says it is pending"          "$out" "name:   PENDING: answer codex's folder-trust question"
has "tells Ben what to do"        "$out" "is asking whether to trust $B/work"
pt="$(print -r -- "$out" | sed -n 's/.*jump:   tmux select-window -t //p')"
grep -q '"thread_name":"trusted-later"' $B/home/session_index.jsonl 2>/dev/null \
  && bad "named before the question was answered" || ok "not named before the answer"
sleep 1
[[ -s $B/home/answered ]] && bad "SOMETHING ANSWERED THE TRUST DIALOG: $(<$B/home/answered)" \
  || ok "nothing answered the trust dialog for Ben"
tm send-keys -t "$pt" Enter       # Ben answers
named=0
for i in {1..40}; do
  grep -q '"thread_name":"trusted-later"' $B/home/session_index.jsonl 2>/dev/null && { named=1; break }
  sleep 0.2
done
(( named )) && ok "named after the answer" || bad "trusted-later never reached the index"

reset_panes
hd "--no-wait returns at once and names in the background"
spawn --no-wait -t bg-name $B/work/03-other.md
(( rc == 0 )) && ok "exit 0" || bad "exit $rc: $out"
has "says naming is in the background" "$out" "being set in the background"
named=0
for i in {1..30}; do
  grep -q '"thread_name":"bg-name"' $B/home/session_index.jsonl 2>/dev/null && { named=1; break }
  sleep 0.2
done
(( named )) && ok "the name landed afterwards" || bad "bg-name never reached the index"

# ------------------------------------------------------------------------------
reset_panes
hd "refusals"
spawn -T "" $B/work/03-other.md;       (( rc == 1 )) && ok "-T '' refused" || bad "-T '' gave $rc"
spawn -T %9999 $B/work/03-other.md;    has "unknown pane refused" "$out" "no such pane"
spawn -e huge $B/work/03-other.md;     has "bad effort refused"   "$out" "effort must be one of"
spawn -t 'two words' $B/work/03-other.md; has "whitespace title refused" "$out" "must not contain whitespace"
spawn $B/nope.md;                      has "missing file refused" "$out" "not a file"
out="$(unset TMUX; CODEX_HOME=$B/home "$SPAWN" $B/work/03-other.md 2>&1)"; rc=$?
(( rc == 1 )) && ok "outside tmux: exit 1" || bad "outside tmux gave $rc"
has "outside tmux: prints the command" "$out" "&& codex -C $B/work"

# ------------------------------------------------------------------------------
hd "never types into codex"
[[ -s $B/home/typed ]] && bad "keystrokes reached codex: $(<$B/home/typed)" || ok "no keystroke reached any codex session"

tm kill-server 2>/dev/null
pkill -f "$B/stub/cdx-name-thread" 2>/dev/null
printf '\n%d passed, %d failed\n' $PASS $FAIL
(( FAIL == 0 ))
