#!/usr/bin/env bash
# hook.sh — Claude Code hook handler for tmux-ai-status.
# Receives a JSON payload on stdin from Claude Code and writes a state file
# that detect.sh / status.sh read for accurate pane state detection.
#
# Register in ~/.claude/settings.json hooks — see ~/Developer/README.md.
#
# Usage: hook.sh <EventName>
#   EventName: UserPromptSubmit | PreToolUse | Stop | Notification

STATE_DIR="${TMPDIR:-/tmp}/claude-tmux-state"
mkdir -p "$STATE_DIR"

EVENT="${1:-}"
input=$(cat)

session_id=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('session_id', ''))
except: pass
" 2>/dev/null)

[ -z "$session_id" ] && exit 0

case "$EVENT" in
    UserPromptSubmit|PreToolUse)
        printf 'running' > "$STATE_DIR/$session_id"
        ;;
    Stop)
        printf 'waiting' > "$STATE_DIR/$session_id"
        ;;
    Notification)
        # Only mark asking for permission-related notifications
        notif_type=$(printf '%s' "$input" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('type', '') or d.get('notificationType', ''))
except: pass
" 2>/dev/null)
        case "$notif_type" in
            *ermission*|tool_use_blocked)
                printf 'asking' > "$STATE_DIR/$session_id"
                ;;
        esac
        ;;
esac
