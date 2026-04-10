#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default: which process names (or cmdline substrings) to detect as AI assistants.
# Override in .tmux.conf with: set -g @ai_status_processes "claude|gemini|aider|llm"
tmux set-option -gq @ai_status_processes "claude|gemini"

# Keybinding: <prefix> + Ctrl-a
tmux bind-key C-a run-shell "$CURRENT_DIR/scripts/panel.sh"

# Append the status indicator to status-right
CURRENT_STATUS=$(tmux show-option -gqv status-right 2>/dev/null)
STATUS_COMPONENT="#($CURRENT_DIR/scripts/status.sh)"
if [ -n "$CURRENT_STATUS" ]; then
    tmux set-option -g status-right "${CURRENT_STATUS} ${STATUS_COMPONENT}"
else
    tmux set-option -g status-right "${STATUS_COMPONENT}"
fi

# Ensure status bar refreshes at least every 5 seconds
INTERVAL=$(tmux show-option -gqv status-interval 2>/dev/null)
if [ -z "$INTERVAL" ] || [ "$INTERVAL" -eq 0 ] || [ "$INTERVAL" -gt 5 ]; then
    tmux set-option -g status-interval 5
fi
