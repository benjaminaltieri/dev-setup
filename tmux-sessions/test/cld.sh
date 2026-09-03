#!/usr/bin/env zsh
# Fast logic tests for the cld family. Stubs `claude`, so no API calls and no
# tmux server.
#
#   ./test/cld.sh
#
# Nothing in this family keeps state: it probes Claude Code for whether a session
# title exists and then resumes or creates. These tests drive that decision by
# feeding the stub each of the probe's possible replies.

emulate -L zsh
setopt no_nomatch

HERE="${0:A:h:h}"
B=/tmp/cld-logic-test
PASS=0; FAIL=0

ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; (( PASS++ )) }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; (( FAIL++ )) }
hd()  { printf '\n\033[1m== %s\033[0m\n' "$1" }

rm -rf $B; mkdir -p $B/stub $B/docs

# The stub answers the probe (any call carrying -p) from $PROBE_REPLY, and
# records the argv of the real launch to $STUB_OUT.
cat > $B/stub/claude <<'EOF'
#!/bin/sh
for a in "$@"; do
  if [ "$a" = "-p" ]; then
    printf '%s\n' "$*" > "$PROBE_ARGV"
    cat "$PROBE_REPLY" >&2
    exit 1
  fi
done
printf '%s\n' "$*" > "$STUB_OUT"
EOF
chmod +x $B/stub/claude

MSG_UNKNOWN='Error: --resume requires a valid session ID or session title when used with --print. Provided value "x" is not a UUID and does not match any session title.'
MSG_KNOWN='Error: No deferred tool marker found in the resumed session. Provide a prompt to continue the conversation.'
MSG_WEIRD='Error: something nobody has seen before'

printf 'contents\n' > $B/docs/01-framework.md
printf 'contents\n' > $B/docs/2026-planning.md

run() {  # run <probe-reply> <command line...>
  local reply="$1"; shift
  print -r -- "$reply" > $B/reply
  rm -f $B/argv $B/probe
  PROBE_REPLY=$B/reply PROBE_ARGV=$B/probe STUB_OUT=$B/argv \
  PATH="$B/stub:$PATH" \
  zsh -c "unset TMUX; source $HERE/shell/cld.zsh; cd $B; $* >$B/stderr 2>&1; :"
  [[ -f $B/argv ]] && cat $B/argv || print -r -- "<not launched>"
}

# ---------------------------------------------------------------- clds --------
hd "clds: title does NOT exist -> create"
r="$(run "$MSG_UNKNOWN" clds no-such-title)"
case "$r" in
  *--session-id*-n*no-such-title*) ok "creates with --session-id and -n ($r)" ;;
  *) bad "expected --session-id ... -n, got: $r" ;;
esac

hd "clds: title EXISTS -> resume by name, vanilla"
r="$(run "$MSG_KNOWN" clds real-title)"
[[ "$r" == "--resume real-title" ]] && ok "resumes by name ($r)" || bad "expected '--resume real-title', got: $r"

hd "clds: unrecognised probe reply fails safe (assume it exists)"
r="$(run "$MSG_WEIRD" clds ambiguous)"
[[ "$r" == "--resume ambiguous" ]] && ok "degrades to vanilla --resume ($r)" || bad "should resume, got: $r"

hd "clds: --new creates even when the title exists"
r="$(run "$MSG_KNOWN" clds --new real-title)"
case "$r" in *--session-id*) ok "forced new ($r)" ;; *) bad "expected --session-id, got: $r" ;; esac
[[ -f $B/probe ]] && bad "--new should skip the probe" || ok "--new skips the probe"

# ---------------------------------------------------------------- title -------
hd "cldp: title derivation"
t() {  # t <path> <expected>
  local got="$(zsh -c "source $HERE/shell/cld.zsh; _cld_title_from_path '$1'")"
  [[ "$got" == "$2" ]] && ok "$1 -> $got" || bad "$1 -> got '$got', want '$2'"
}
t 01-framework.md              framework
t 07_data-access.md            data-access
t 23.session-log.md            session-log
t 004-three-digits.md          three-digits
t docs/01-plan.md              plan
t /abs/14-session-log-2026-08-14.md session-log-2026-08-14
t 2026-planning.md             2026-planning
t 1234-four-digits.md          1234-four-digits
t 01framework.md               01framework
t plain-name.md                plain-name

# ---------------------------------------------------------------- cldp --------
hd "cldp: new title -> create, @-tagging the ORIGINAL path, prompt last"
r="$(run "$MSG_UNKNOWN" cldp docs/01-framework.md)"
if [[ "$r" == *"-n framework"* ]]; then ok "title stripped to 'framework'"; else bad "title wrong: $r"; fi
if [[ "$r" == *"@docs/01-framework.md" ]]; then
  ok "kickoff is the original path, as the final argument"
else
  bad "expected trailing '@docs/01-framework.md', got: $r"
fi
if [[ "$r" == *"@docs/01-framework.md"*[[:graph:]]* && "$r" != *"@docs/01-framework.md" ]]; then
  bad "prompt is not last"
fi
case "$r" in *--session-id*) ok "created with --session-id" ;; *) bad "no --session-id: $r" ;; esac

hd "cldp: existing title -> resume, and do NOT resend the prompt"
r="$(run "$MSG_KNOWN" cldp docs/01-framework.md)"
[[ "$r" == "--resume framework" ]] && ok "resumes without re-tagging ($r)" || bad "expected bare '--resume framework', got: $r"

hd "cldp: --prefix names the workstream"
r="$(run "$MSG_UNKNOWN" cldp -P my-project docs/01-framework.md)"
[[ "$r" == *"-n my-project-framework"* ]] && ok "prefix joined with a hyphen ($r)" || bad "got: $r"
r="$(run "$MSG_UNKNOWN" cldp --prefix my-project docs/01-framework.md)"
[[ "$r" == *"-n my-project-framework"* ]] && ok "long form works" || bad "long form: $r"
# a trailing separator on the prefix must not double up
r="$(run "$MSG_UNKNOWN" cldp -P 'my-project-' docs/01-framework.md)"
[[ "$r" == *"-n my-project-framework"* ]] && ok "trailing separator trimmed" || bad "got: $r"
# the prefix must reach the title, not be forwarded to claude
[[ "$r" == *"--prefix"* ]] && bad "--prefix leaked through to claude" || ok "--prefix consumed, not forwarded"
r="$(run "$MSG_UNKNOWN" cldp -P 'has spaces' docs/01-framework.md)"
[[ "$r" == "<not launched>" ]] && ok "a prefix with whitespace is refused" || bad "launched: $r"

hd "cldp: --title, and how it combines with --prefix"
r="$(run "$MSG_UNKNOWN" cldp -t explicit-name docs/01-framework.md)"
[[ "$r" == *"-n explicit-name"* ]] && ok "--title overrides the derived title ($r)" || bad "got: $r"
r="$(run "$MSG_UNKNOWN" cldp -P my-project -t explicit-name docs/01-framework.md)"
[[ "$r" == *"-n my-project-explicit-name"* ]] && ok "prefix applies to --title too" || bad "got: $r"
# the title still decides resume-vs-create, so the probe must use the final one
run "$MSG_KNOWN" cldp -P my-project docs/01-framework.md >/dev/null
[[ "$(<$B/probe)" == *"--resume my-project-framework"* ]] && ok "the probe checks the prefixed title" || bad "probe used: $(<$B/probe)"

hd "cldp: model variants"
r="$(run "$MSG_UNKNOWN" cldn docs/01-framework.md)"
[[ "$r" == *"--model sonnet"* ]] && ok "cldn -> sonnet ($r)" || bad "cldn: $r"
r="$(run "$MSG_UNKNOWN" cldo docs/01-framework.md)"
[[ "$r" == *"--model opus"* ]] && ok "cldo -> opus" || bad "cldo: $r"
r="$(run "$MSG_UNKNOWN" cldf docs/01-framework.md)"
[[ "$r" == *"--model fable"* ]] && ok "cldf -> fable" || bad "cldf: $r"
r="$(run "$MSG_UNKNOWN" cldp docs/01-framework.md)"
[[ "$r" == *"--model"* ]] && bad "cldp should pass no --model: $r" || ok "cldp passes no --model"

hd "cldp: model applies on the resume path too"
r="$(run "$MSG_KNOWN" cldo docs/01-framework.md)"
[[ "$r" == "--resume framework --model opus" ]] && ok "resume carries the model ($r)" || bad "got: $r"

hd "cldp: a missing file is refused before anything launches"
r="$(run "$MSG_UNKNOWN" cldp docs/nope-does-not-exist.md)"
[[ "$r" == "<not launched>" ]] && ok "refused to launch" || bad "launched anyway: $r"
grep -q 'not a file' $B/stderr && ok "says why" || bad "no explanation"

hd "cldp: a directory is refused"
r="$(run "$MSG_UNKNOWN" cldp docs)"
[[ "$r" == "<not launched>" ]] && ok "directory refused" || bad "launched on a directory: $r"

hd "cldp: extra args are passed through to claude"
r="$(run "$MSG_UNKNOWN" cldp docs/01-framework.md --effort high)"
[[ "$r" == *"--effort high"*"@docs/01-framework.md" ]] && ok "flags precede the prompt ($r)" || bad "got: $r"

hd "cldp: --new forces a fresh session"
r="$(run "$MSG_KNOWN" cldp --new docs/01-framework.md)"
case "$r" in *--session-id*"@docs/01-framework.md") ok "forced new and re-tagged ($r)" ;; *) bad "got: $r" ;; esac

hd "no state is written anywhere"
[[ -e $HOME/.config/tmux-snap/sessions ]] && bad "a registry directory exists again" || ok "no registry directory"

printf '\n\033[1m== summary\033[0m\n'
printf '  passed: %s\n  failed: %s\n' "$PASS" "$FAIL"
rm -rf $B
(( FAIL == 0 ))
