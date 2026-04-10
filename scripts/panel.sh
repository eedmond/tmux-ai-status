#!/usr/bin/env bash
# panel.sh — opens the AI assistant panel popup, then jumps to the selection.

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

[ ! -s "$TMPFILE" ] && exit 0

PANE_ID=$(cat "$TMPFILE")
[ -z "$PANE_ID" ] && exit 0

TARGET=$(tmux display-message -p -t "$PANE_ID" \
    "#{session_name}:#{window_index}" 2>/dev/null)

tmux switch-client -t "$TARGET"
tmux select-pane   -t "$PANE_ID"
