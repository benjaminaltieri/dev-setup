# cld family - start or resume Claude Code sessions by name, or from a prompt file.
#
# Source from ~/.zshrc:
#   source ~/obsidian/quantumscape/tmux-setup/shell/cld.zsh
#
# Companions defined as plain aliases in ~/misc/dev-setup/shell_aliases.sh:
#   cld     claude                              cldcon  claude --continue
#   cldres  claude --resume  (picker)           cldfork claude --fork-session --resume
#
# Defined here, because they need argument handling:
#   clds <name>        resume the session titled <name>, or start it
#   cldp <file>        same, but the title comes from a prompt file's name and the
#                      session is kicked off by @-tagging that file
#   cldn/cldo/cldf     cldp on sonnet / opus / fable
#
# Nothing here keeps state. Claude Code already stores the name (it calls it the
# session "title") and resolves it, so the only decision made here is
# resume-vs-create. Titles resolve per project, keyed on the current directory,
# so a name only has to be unique within the repo you are in.

# --- does Claude Code know this session title, in this project? ---------------
# `claude -p '' --resume <title>` resolves the title and then rejects the empty
# prompt, which is a lookup with no API turn (verified: transcript unchanged,
# ~1-2s). The two failures are distinguishable:
#   unknown title -> "does not match any session title"
#   known title   -> complains about the empty prompt instead
#
# This reads an error string, which is internal and may change between releases.
# So the unknown-title verdict requires that exact phrase, and anything
# unrecognised is treated as "probably exists" -- that way a changed message
# degrades to vanilla `--resume` behaviour (at worst the picker opens) rather
# than silently starting a duplicate session.
_cld_title_exists() {
  local out
  out="$(command claude -p '' --resume "$1" </dev/null 2>&1)"
  [[ "$out" == *"does not match any session title"* ]] && return 1
  return 0
}

# --- prompt file path -> session title ---------------------------------------
# Drops the directory, the extension, and a leading ordinal such as "01-",
# "07_" or "23.". The ordinal is capped at three digits so that a four-digit
# year survives: 2026-planning.md stays 2026-planning.
_cld_title_from_path() {
  emulate -L zsh
  local base="${1:t}"
  base="${base%.*}"
  if [[ "$base" =~ '^[0-9]{1,3}[-_.](.+)$' ]]; then
    base="${match[1]}"
  fi
  base="${base%%[-_.]}"
  print -r -- "$base"
}

# --- shared launcher ---------------------------------------------------------
# _cld_launch <title> <model|""> <prompt|""> <force_new> [claude args...]
_cld_launch() {
  emulate -L zsh
  local title="$1" model="$2" kickoff="$3" force_new="$4"
  shift 4

  local -a margs
  [[ -n "$model" ]] && margs=(--model "$model")

  if (( force_new )) || ! _cld_title_exists "$title"; then
    # Choosing the id up front is what lets the pane be labelled immediately:
    # Claude Code does not write its session file until the first user prompt, so
    # without this a tmux-snap taken before you type would miss the session.
    local sid="${$(uuidgen):l}"
    # -t "$TMUX_PANE" is required: `set-option -p` with no target does NOT act on
    # the calling pane, it acts on the globally active pane, so an unqualified
    # stamp lands on whatever the user is looking at.
    if [[ -n "$TMUX" && -n "$TMUX_PANE" ]]; then
      tmux set-option -p -t "$TMUX_PANE" @cc_name "$title" 2>/dev/null
      tmux set-option -p -t "$TMUX_PANE" @cc_sid  "$sid"   2>/dev/null
    fi
    if [[ -n "$kickoff" ]]; then
      print -ru2 -- "cld: starting '$title'${model:+ on $model} with $kickoff"
      command claude --session-id "$sid" -n "$title" "${margs[@]}" "$@" "$kickoff"
    else
      print -ru2 -- "cld: starting '$title'${model:+ on $model}"
      command claude --session-id "$sid" -n "$title" "${margs[@]}" "$@"
    fi
    return $?
  fi

  # On the resume path the id is not ours to know; tmux-snap picks it up from
  # Claude Code's own session file once the session registers. The prompt is
  # deliberately NOT resent: reopening a session should not cost a turn.
  [[ -n "$TMUX" && -n "$TMUX_PANE" ]] && \
    tmux set-option -p -t "$TMUX_PANE" @cc_name "$title" 2>/dev/null
  print -ru2 -- "cld: resuming '$title'${model:+ on $model}"
  command claude --resume "$title" "${margs[@]}" "$@"
}

# --- clds: session by name ---------------------------------------------------
clds() {
  emulate -L zsh
  setopt local_options no_nomatch

  local force_new=0
  while (( $# )); do
    case "$1" in
      -n|--new) force_new=1; shift ;;
      -h|--help)
        print -r -- "usage: clds <name> [claude args...]"
        print -r -- "         resume the session titled <name>, or start it if there is none"
        print -r -- "       clds -n <name>      always start a new session"
        print -r -- ""
        print -r -- "see also: cldp (title from a prompt file), cld, cldcon, cldres, cldfork"
        return 0 ;;
      --) shift; break ;;
      *)  break ;;
    esac
  done

  local name="$1"
  if [[ -z "$name" ]]; then
    print -ru2 -- "clds: usage: clds <name>"
    return 2
  fi
  shift

  _cld_launch "$name" "" "" "$force_new" "$@"
}

# --- cldp and friends: title and kickoff from a prompt file ------------------
_cld_prompt_session() {
  emulate -L zsh
  setopt local_options no_nomatch

  local model="$1"; shift
  local fn="${funcstack[2]:-cldp}"
  local force_new=0

  while (( $# )); do
    case "$1" in
      -n|--new) force_new=1; shift ;;
      -h|--help)
        print -r -- "usage: $fn <prompt-file> [claude args...]"
        print -r -- "         title  = file name, minus directory, extension and a leading ordinal"
        print -r -- "         kickoff= the session opens with '@<the path you gave>'"
        print -r -- "       $fn -n <prompt-file>   always start a new session"
        print -r -- ""
        print -r -- "  cldp  default model     cldo  opus"
        print -r -- "  cldn  sonnet            cldf  fable"
        return 0 ;;
      --) shift; break ;;
      *)  break ;;
    esac
  done

  # NOT `local path=`: in zsh `path` is tied to PATH, so a local of that name
  # blanks out PATH for the whole call and `command claude` stops resolving.
  # `prompt` is likewise a synonym for PS1, hence `kickoff` in _cld_launch.
  local pfile="$1"
  if [[ -z "$pfile" ]]; then
    print -ru2 -- "$fn: usage: $fn <prompt-file> [claude args...]"
    return 2
  fi
  shift

  if [[ ! -f "$pfile" ]]; then
    print -ru2 -- "$fn: not a file: $pfile"
    return 2
  fi

  local title="$(_cld_title_from_path "$pfile")"
  if [[ -z "$title" ]]; then
    print -ru2 -- "$fn: could not derive a title from: $pfile"
    return 2
  fi

  # @-mentions are whitespace delimited, so a path containing spaces would be
  # truncated at the first one.
  if [[ "$pfile" == *[[:space:]]* ]]; then
    print -ru2 -- "$fn: warning: path contains whitespace; the @mention may not resolve"
  fi

  _cld_launch "$title" "$model" "@$pfile" "$force_new" "$@"
}

cldp() { _cld_prompt_session ""       "$@" }
cldn() { _cld_prompt_session sonnet   "$@" }
cldo() { _cld_prompt_session opus     "$@" }
cldf() { _cld_prompt_session fable    "$@" }

# --- completion --------------------------------------------------------------
# clds completes session titles recorded in the newest tmux-snap snapshot.
# cldp and friends complete file paths, since their argument is a file.
_clds() {
  # No `emulate -L zsh` here: completion widgets run in a context the completion
  # system has already prepared, and resetting options to zsh defaults stops
  # _describe from adding any matches at all.
  local -a names
  local snap="${TMUX_SNAP_DIR:-$HOME/.config/tmux-snap}/latest.json"
  [[ -r "$snap" ]] || return 1
  names=( ${(f)"$(jq -r '[.sessions[].windows[].panes[] | select(.claude!=null) | .claude.name | select(.!=null)] | unique | .[]' "$snap" 2>/dev/null)"} )
  names=( ${names:#} )
  (( ${#names} )) || return 1
  _describe -t clds-sessions 'claude session' names
}
compdef _clds clds 2>/dev/null || true
compdef _files cldp cldn cldo cldf 2>/dev/null || true
