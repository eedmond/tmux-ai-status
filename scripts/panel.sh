#!/usr/bin/env bash
# panel.sh — opens the AI assistant panel popup, then acts on the selection.

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

tmux display-popup \
    -E \
    -w "88%" \
    -h "75%" \
    -b "rounded" \
    -T " AI Assistants " \
    "$PLUGIN_DIR/scripts/panel_inner.sh '$TMPFILE'"

# Nothing was selected
[ ! -s "$TMPFILE" ] && exit 0

ACTION=$(head -1 "$TMPFILE")
PANE_ID=$(sed -n '2p' "$TMPFILE")

[ -z "$PANE_ID" ] && exit 0

# Resolve the session:window for the selected pane
TARGET=$(tmux display-message -p -t "$PANE_ID" \
    "#{session_name}:#{window_index}" 2>/dev/null)
SESSION=$(tmux display-message -p -t "$PANE_ID" \
    "#{session_name}" 2>/dev/null)

if [ "$ACTION" = "popup" ]; then
    # Pre-select the pane in its session, then attach in a popup so the user
    # sees it front-and-centre. We briefly modify session state but it's
    # immediately visible to the user in the popup.
    tmux select-window -t "$TARGET"
    tmux select-pane   -t "$PANE_ID"
    tmux display-popup \
        -E \
        -w "80%" \
        -h "85%" \
        -b "rounded" \
        -T " AI Assistant " \
        "tmux attach-session -t '$SESSION'"

elif [ "$ACTION" = "jump" ]; then
    tmux switch-client -t "$TARGET"
    tmux select-pane   -t "$PANE_ID"
fi
