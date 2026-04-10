#!/usr/bin/env bash
# detect.sh — scan all tmux panes and emit AI assistant panes as TSV:
#   pane_id  session  window_name  window_index  pane_index  ai_type  state  summary
#
# State heuristics (best-effort from captured pane content):
#   running  — spinner chars or "Thinking/Working/Running" visible
#   idle     — pane alive, no running indicators (at prompt)

AI_PATTERN=$(tmux show-option -gqv @ai_status_processes 2>/dev/null)
AI_PATTERN="${AI_PATTERN:-claude|gemini}"

# Look up the conversation summary for a Claude pane by matching its PID
# against ~/.claude/sessions/ and then looking up history.jsonl.
get_claude_summary() {
    local sessions_dir="$HOME/.claude/sessions"
    local history="$HOME/.claude/history.jsonl"
    [ ! -d "$sessions_dir" ] || [ ! -f "$history" ] && return

    local session_id=""
    for check_pid in "$@"; do
        local sf
        sf=$(grep -rl "\"pid\":$check_pid" "$sessions_dir" 2>/dev/null | head -1)
        if [ -n "$sf" ]; then
            session_id=$(python3 -c "
import json
try:
    print(json.load(open('$sf')).get('sessionId', ''))
except: pass
" 2>/dev/null)
            [ -n "$session_id" ] && break
        fi
    done

    [ -z "$session_id" ] && return

    grep -F "\"$session_id\"" "$history" 2>/dev/null | tail -1 | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print((d.get('display') or '').replace('\n', ' ')[:60])
except: pass
" 2>/dev/null
}

tmux list-panes -a \
    -F "#{pane_id} #{session_name} #{window_name} #{window_index} #{pane_index} #{pane_pid} #{pane_current_command}" \
    2>/dev/null | \
while read -r pane_id session window_name window_idx pane_idx pid cmd; do

    ai_type=""
    child_pids=()

    # Fast path: pane_current_command matches directly (e.g. "gemini")
    if echo "$cmd" | grep -qiE "^($AI_PATTERN)$"; then
        ai_type="$cmd"
    else
        # Slower path: check pane_pid and its direct children.
        # pane_pid is the shell for normally-launched panes; the AI process
        # is a child (or the pid itself if launched without a shell).
        child_pids=($(pgrep -P "$pid" 2>/dev/null))
        for check_pid in "$pid" "${child_pids[@]}"; do
            cmdline=$(ps -o args= -p "$check_pid" 2>/dev/null) || continue
            if echo "$cmdline" | grep -qiE "(^|[/ ])($AI_PATTERN)"; then
                ai_type=$(echo "$cmdline" | grep -oiE "(^|[/ ])($AI_PATTERN)" | \
                    grep -oiE "($AI_PATTERN)$" | head -1 | tr '[:upper:]' '[:lower:]')
                break
            fi
        done
    fi

    [ -z "$ai_type" ] && continue

    # State detection.
    # - Capture 3 lines for "running" (tight window avoids old spinners in history)
    # - Capture 10 lines for "asking" (question/choices may span several lines)
    last3=$(tmux capture-pane -t "$pane_id" -p -S -3 2>/dev/null)
    content=$(tmux capture-pane -t "$pane_id" -p -S -10 2>/dev/null)
    state="idle"
    if printf '%s\n' "$last3" | grep -qE \
        '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|Thinking[….]|Working[….]|Running[^a-zA-Z]'; then
        state="running"
    elif printf '%s\n' "$content" | grep -qE \
        '❯[[:space:]]+(Yes|No|Allow|Deny|Proceed|Cancel|Continue|Skip|Approve|y|n)|\[y/n\]|\[Y/n\]|\[y/N\]|Yes, and don'"'"'t ask'; then
        # ❯ alone is Claude's generic input cursor; only match when followed by
        # a known option word (tool permission dialogs, confirmation prompts)
        state="asking"
    fi

    # Summary: Claude only (reads ~/.claude/sessions + history.jsonl)
    summary=""
    if [ "$ai_type" = "claude" ]; then
        summary=$(get_claude_summary "$pid" "${child_pids[@]}")
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pane_id" "$session" "$window_name" \
        "$window_idx" "$pane_idx" "$ai_type" "$state" "$summary"
done
