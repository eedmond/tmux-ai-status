#!/usr/bin/env bash
# panel_preview.sh — live preview of the selected AI pane.
# Runs in the right pane of the agents window.
# Updates whenever the fzf selection changes (written to $1 by panel_inner.sh).

SELECTION_FILE="$1"
LAST_CONTENT=""
LAST_PANE=""

# Hide cursor to reduce flicker
printf '\033[?25l'
trap 'printf "\033[?25h"' EXIT

while true; do
    PANE_ID=$(cat "$SELECTION_FILE" 2>/dev/null)

    if [ -z "$PANE_ID" ]; then
        sleep 0.2
        continue
    fi

    CONTENT=$(tmux capture-pane -t "$PANE_ID" -p -e 2>/dev/null)

    # Only redraw when pane or content has changed
    if [ "$PANE_ID" != "$LAST_PANE" ] || [ "$CONTENT" != "$LAST_CONTENT" ]; then
        printf '\033[H'   # cursor home — overwrite in place, no clear flash
        printf '%s' "$CONTENT"
        LAST_CONTENT="$CONTENT"
        LAST_PANE="$PANE_ID"
    fi

    sleep 0.2
done
