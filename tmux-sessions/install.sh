#!/usr/bin/env bash
# Install the tmux session-persistence tooling on this machine.
#
#   ./tmux-sessions/install.sh            # install / re-install
#   ./tmux-sessions/install.sh --uninstall
#
# Idempotent: safe to run repeatedly. Existing files are backed up, never
# silently overwritten.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
PLIST_LABEL="com.benaltieri.tmux-snap"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
ZSHRC="$HOME/.zshrc"
SOURCE_LINE="[[ -f \"\$HOME/misc/dev-setup/tmux-sessions/shell/cld.zsh\" ]] && source \"\$HOME/misc/dev-setup/tmux-sessions/shell/cld.zsh\""

say() { printf '  %s\n' "$*"; }

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "Uninstalling tmux session tooling..."
  launchctl unload "$PLIST_DEST" 2>/dev/null || true
  rm -f "$PLIST_DEST"; say "removed the snapshot timer"
  for b in tmux-snap tmux-restore cld-spawn cdx-spawn; do rm -f "$HOME/.local/bin/$b"; done
  say "removed ~/.local/bin symlinks"
  say "left alone: ~/.zshrc source line, byobu config, and ~/.config/tmux-snap snapshots"
  exit 0
fi

echo "Installing tmux session tooling from $HERE"

# 1. commands on PATH
mkdir -p "$HOME/.local/bin"
for b in tmux-snap tmux-restore cld-spawn cdx-spawn; do
  ln -sfn "$HERE/bin/$b" "$HOME/.local/bin/$b"
done
say "linked tmux-snap, tmux-restore, cld-spawn, cdx-spawn into ~/.local/bin"

# 2. shell functions (clds, cldp, cldn/cldo/cldf), appended rather than copied so
#    an existing .zshrc is never clobbered
if grep -qF 'tmux-sessions/shell/cld.zsh' "$ZSHRC" 2>/dev/null; then
  say ".zshrc already sources cld.zsh"
else
  {
    printf '\n# Named, resumable Claude Code sessions (clds, cldp), with tab completion.\n'
    printf '# Sourced late so compinit has already run.\n'
    printf '%s\n' "$SOURCE_LINE"
  } >> "$ZSHRC"
  say "appended the cld.zsh source line to ~/.zshrc"
fi

# 3. byobu key bindings (C-a C-s snapshot, C-a C-r restore)
BYOBU_DIR="${BYOBU_CONFIG_DIR:-$HOME/.config/byobu}"
if [[ -d "$BYOBU_DIR" ]]; then
  if [[ -f "$BYOBU_DIR/.tmux.conf" ]] && ! cmp -s "$HERE/config/byobu.tmux.conf" "$BYOBU_DIR/.tmux.conf"; then
    cp "$BYOBU_DIR/.tmux.conf" "$BYOBU_DIR/.tmux.conf.bak-$STAMP"
    say "backed up the existing byobu config to .tmux.conf.bak-$STAMP"
  fi
  cp "$HERE/config/byobu.tmux.conf" "$BYOBU_DIR/.tmux.conf"
  say "installed byobu key bindings into $BYOBU_DIR/.tmux.conf"
  tmux source-file "$BYOBU_DIR/.tmux.conf" 2>/dev/null && say "loaded them into the running server" || true
else
  say "no byobu config dir at $BYOBU_DIR; skipped key bindings"
fi

# 4. five-minute snapshot timer
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|__TMUX_SNAP__|$HERE/bin/tmux-snap|g" -e "s|__HOME__|$HOME|g" \
    "$HERE/config/$PLIST_LABEL.plist" > "$PLIST_DEST"
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"
say "installed and loaded the 5-minute snapshot timer"

echo
echo "Done. Open a new shell, or: source ~/.zshrc"
echo "Verify with: clds -h ; cld-spawn -h ; cdx-spawn -h ; tmux-snap --stdout | head -3"
