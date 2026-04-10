#!/usr/bin/env bash
# detect.sh — scan all tmux panes and emit AI assistant panes as TSV:
#   pane_id  session  window_name  window_index  pane_index  ai_type  state  summary
#
# State sources (Claude):
#   hook state file  — written by hook.sh via Claude Code hooks (most accurate)
#   pane content     — fallback when no hook state exists yet
#
# State sources (Gemini / others):
#   pane content     — braille spinner detection

AI_PATTERN=$(tmux show-option -gqv @ai_status_processes 2>/dev/null)
AI_PATTERN="${AI_PATTERN:-claude|gemini}"

HOOK_STATE_DIR="${TMPDIR:-/tmp}/claude-tmux-state"

# Returns the Claude session ID for the given PIDs (first match wins).
get_claude_session_id() {
    local sessions_dir="$HOME/.claude/sessions"
    [ ! -d "$sessions_dir" ] && return
    for check_pid in "$@"; do
        local sf
        # Check newest files first — the active session is almost always recently modified.
        sf=$(ls -t "$sessions_dir"/*.json 2>/dev/null | xargs grep -l "\"pid\":$check_pid" 2>/dev/null | head -1)
        if [ -n "$sf" ]; then
            python3 -c "
import json
try:
    print(json.load(open('$sf')).get('sessionId', ''))
except: pass
" 2>/dev/null
            return
        fi
    done
}

# Returns conversation display summary for the given Claude session ID.
get_claude_summary_by_sid() {
    local session_id="$1"
    local history="$HOME/.claude/history.jsonl"
    [ -z "$session_id" ] || [ ! -f "$history" ] && return
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
    ai_pid=""
    child_pids=()

    # Fast path: pane_current_command matches directly (e.g. "gemini")
    if echo "$cmd" | grep -qiE "^($AI_PATTERN)$"; then
        ai_type="$cmd"
        ai_pid="$pid"
    else
        # Slower path: check pane_pid and its direct children.
        child_pids=($(pgrep -P "$pid" 2>/dev/null))
        for check_pid in "$pid" "${child_pids[@]}"; do
            cmdline=$(ps -o args= -p "$check_pid" 2>/dev/null) || continue
            if echo "$cmdline" | grep -qiE "(^|[/ ])($AI_PATTERN)"; then
                ai_type=$(echo "$cmdline" | grep -oiE "(^|[/ ])($AI_PATTERN)" | \
                    grep -oiE "($AI_PATTERN)$" | head -1 | tr '[:upper:]' '[:lower:]')
                ai_pid="$check_pid"
                break
            fi
        done
    fi

    [ -z "$ai_type" ] && continue

    visible=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null)
    state="waiting"
    summary=""

    if [ "$ai_type" = "claude" ]; then
        # Look up session ID — used for both hook state and conversation summary.
        claude_sid=$(get_claude_session_id "$pid" "${child_pids[@]}")

        # Hook state is the primary source (written by hook.sh via Claude Code hooks).
        hook_state=""
        [ -n "$claude_sid" ] && hook_state=$(cat "$HOOK_STATE_DIR/$claude_sid" 2>/dev/null)

        if [ "$hook_state" = "running" ]; then
            state="running"
        else
            last1=$(printf '%s\n' "$visible" | tail -1)
            last2=$(printf '%s\n' "$visible" | tail -2)
            last3=$(printf '%s\n' "$visible" | tail -3)
            if [ "$hook_state" = "asking" ]; then
                state="asking"
            elif printf '%s\n' "$last1" | grep -qi "enter to select\|esc to cancel"; then
                state="asking"
            elif printf '%s\n' "$last3" | grep -qE \
                '❯[[:space:]]+(Yes|No|Allow|Deny|Proceed|Cancel|Continue|Skip|Approve|y|n)|\[y/n\]|\[Y/n\]|\[y/N\]|Yes, and don'"'"'t ask'; then
                state="asking"
            elif [ -z "$hook_state" ] && printf '%s\n' "$last2" | grep -qi "esc to interrupt"; then
                # No hook state yet (hooks not configured or first run) — fall back to pane content.
                state="running"
            fi
        fi

        summary=$(get_claude_summary_by_sid "$claude_sid")
    else
        # Gemini and others: braille spinner detection works well.
        last5=$(tmux capture-pane -t "$pane_id" -p -S -5 2>/dev/null)
        if printf '%s\n' "$last5" | grep -qE '^[[:space:]]*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏][[:space:]]'; then
            state="running"
        elif printf '%s\n' "$visible" | grep -qE \
            '❯[[:space:]]+(Yes|No|Allow|Deny|Proceed|Cancel|Continue|Skip|Approve|y|n)|\[y/n\]|\[Y/n\]|\[y/N\]|Yes, and don'"'"'t ask'; then
            state="asking"
        fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$pane_id" "$session" "$window_name" \
        "$window_idx" "$pane_idx" "$ai_type" "$state" "$summary"
done
