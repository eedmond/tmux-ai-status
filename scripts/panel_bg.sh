#!/usr/bin/env bash
# panel_bg.sh — switches the background to the selected agent pane, zoomed to fill the window.
# Unzooms the previously previewed pane before switching.

PANE_ID="$1"
[ -z "$PANE_ID" ] && exit 0

STATE_FILE="${TMPDIR:-/tmp}/ai-panel-bg-state"

# Restore previous pane's zoom state before switching away
if [ -f "$STATE_FILE" ]; then
    read -r PREV_PANE PREV_WAS_ZOOMED 2>/dev/null < "$STATE_FILE"
    if [ -n "$PREV_PANE" ] && [ "$PREV_PANE" != "$PANE_ID" ] && [ "$PREV_WAS_ZOOMED" = "0" ]; then
        # We zoomed it — unzoom it now
        tmux resize-pane -Z -t "$PREV_PANE" 2>/dev/null
    fi
fi

# Check if target window is already zoomed (before we touch it)
WAS_ZOOMED=$(tmux display-message -p -t "$PANE_ID" "#{window_zoomed_flag}" 2>/dev/null)
WIN=$(tmux display-message -p -t "$PANE_ID" "#{window_id}" 2>/dev/null)
[ -z "$WIN" ] && exit 0

# Save state for next call
printf '%s %s\n' "$PANE_ID" "$WAS_ZOOMED" > "$STATE_FILE"

# Switch background to agent window, select the pane, zoom it
tmux switch-client -t "$WIN" 2>/dev/null
tmux select-pane   -t "$PANE_ID" 2>/dev/null
[ "$WAS_ZOOMED" = "0" ] && tmux resize-pane -Z -t "$PANE_ID" 2>/dev/null
