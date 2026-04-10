#!/usr/bin/env bash
# panel.sh — full-width popup with live agent preview on the right.
#
# While the popup is open:
#   enter       — jump to the selected pane
#   esc         — close popup, restore original window

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOCKFILE="${TMPDIR:-/tmp}/ai-panel.lock"
[ -f "$LOCKFILE" ] && exit 0
touch "$LOCKFILE"

TMPFILE=$(mktemp)
ORIGIN=$(tmux display-message -p "#{window_id}")

cleanup() {
    rm -f "$TMPFILE" "$LOCKFILE"
}
trap cleanup EXIT

tmux display-popup \
    -E \
    -w "95%" \
    -h "90%" \
    -b "rounded" \
    -T " AI Assistants " \
    "bash '$PLUGIN_DIR/scripts/panel_inner.sh' '$TMPFILE'"

RESULT=$(cat "$TMPFILE" 2>/dev/null)

if [ -z "$RESULT" ]; then
    tmux switch-client -t "$ORIGIN" 2>/dev/null
else
    TARGET=$(tmux display-message -p -t "$RESULT" \
        "#{session_name}:#{window_index}" 2>/dev/null)
    tmux switch-client -t "$TARGET" 2>/dev/null
    tmux select-pane   -t "$RESULT" 2>/dev/null
fi
