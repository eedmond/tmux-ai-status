#!/usr/bin/env bash
# detect.sh — scan all tmux panes and emit AI assistant panes as TSV:
#   pane_id  session  window_name  window_index  pane_index  ai_type  state
#
# State heuristics (best-effort from captured pane content):
#   running  — spinner chars or "Thinking/Working/Running" visible
#   waiting  — pane alive, no running indicators (at prompt)
#   idle     — AI process not detected in pane's process tree

AI_PATTERN=$(tmux show-option -gqv @ai_status_processes 2>/dev/null)
AI_PATTERN="${AI_PATTERN:-claude|gemini}"

tmux list-panes -a \
    -F "#{pane_id} #{session_name} #{window_name} #{window_index} #{pane_index} #{pane_pid} #{pane_current_command}" \
    2>/dev/null | \
while read -r pane_id session window_name window_idx pane_idx pid cmd; do

    ai_type=""

    # Fast path: pane_current_command matches directly (e.g. "gemini")
    if echo "$cmd" | grep -qiE "^($AI_PATTERN)$"; then
        ai_type="$cmd"
    else
        # Slower path: check the full process cmdline (handles Node-based CLIs
        # like Claude Code where pane_current_command reports "node")
        cmdline=$(ps -o args= -p "$pid" 2>/dev/null)
        matched=$(echo "$cmdline" | grep -oiE "(^|[/ ])($AI_PATTERN)( |\$)" | \
            grep -oiE "$AI_PATTERN" | head -1)
        [ -n "$matched" ] && ai_type="$matched"
    fi

    [ -z "$ai_type" ] && continue

    # State detection via captured pane content (last 6 lines)
    content=$(tmux capture-pane -t "$pane_id" -p -S -6 2>/dev/null)
    state="waiting"
    # Running: spinner chars or common "thinking" phrases
    if printf '%s' "$content" | grep -qP \
        '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|Thinking…|Working…|Running\b|◒|↓'; then
        state="running"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pane_id" "$session" "$window_name" \
        "$window_idx" "$pane_idx" "$ai_type" "$state"
done
