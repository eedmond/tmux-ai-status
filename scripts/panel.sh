#!/usr/bin/env bash
# panel.sh — full-width popup with live agent preview on the right.
#
# While the popup is open:
#   <leader>+l  — close popup, stay in the current agent window (interact inline)
#   <leader>+h  — reopen this panel
#   enter       — jump to the selected pane
#   esc         — close popup, restore original window

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

LOCKFILE="${TMPDIR:-/tmp}/ai-panel.lock"
[ -f "$LOCKFILE" ] && exit 0
touch "$LOCKFILE"

TMPFILE=$(mktemp)
ORIGIN=$(tmux display-message -p "#{window_id}")

# Temporarily rebind <leader>+l/<leader>+h while panel is open
tmux bind-key l run-shell "printf 'STAY' > '$TMPFILE'; tmux display-popup -C"
tmux bind-key h run-shell "bash '$PLUGIN_DIR/scripts/panel.sh'"

cleanup() {
    tmux bind-key l select-pane -R
    tmux bind-key h select-pane -L
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
elif [ "$RESULT" = "STAY" ]; then
    : # already at the agent window from the focus-event switch, nothing to do
else
    TARGET=$(tmux display-message -p -t "$RESULT" \
        "#{session_name}:#{window_index}" 2>/dev/null)
    tmux switch-client -t "$TARGET" 2>/dev/null
    tmux select-pane   -t "$RESULT" 2>/dev/null
fi
