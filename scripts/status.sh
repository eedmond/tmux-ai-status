#!/usr/bin/env bash
# status.sh — fast status bar component.
# Outputs a compact indicator like:  󱙺 3  ▶ 1  ◎ 2
# Returns nothing if no AI panes are found.

AI_PATTERN=$(tmux show-option -gqv @ai_status_processes 2>/dev/null)
AI_PATTERN="${AI_PATTERN:-claude|gemini}"

HOOK_STATE_DIR="${TMPDIR:-/tmp}/claude-tmux-state"

total=0
running=0
asking=0
waiting=0

while IFS=' ' read -r pane_id pid cmd; do
    matched=0
    ai_type=""
    ai_pid=""

    # Detect AI type and process PID in one pass
    if echo "$cmd" | grep -qiE "^($AI_PATTERN)$"; then
        matched=1
        ai_type=$(echo "$cmd" | tr '[:upper:]' '[:lower:]')
        ai_pid="$pid"
    else
        for check_pid in "$pid" $(pgrep -P "$pid" 2>/dev/null); do
            cmdline=$(ps -o args= -p "$check_pid" 2>/dev/null) || continue
            if echo "$cmdline" | grep -qiE "(^|[/ ])($AI_PATTERN)"; then
                matched=1
                ai_type=$(echo "$cmdline" | grep -oiE "(^|[/ ])($AI_PATTERN)" | \
                    grep -oiE "($AI_PATTERN)$" | head -1 | tr '[:upper:]' '[:lower:]')
                ai_pid="$check_pid"
                break
            fi
        done
    fi

    [ "$matched" -eq 0 ] && continue
    total=$((total + 1))

    visible=$(tmux capture-pane -t "$pane_id" -p 2>/dev/null)

    if [ "$ai_type" = "claude" ]; then
        # Look up Claude session ID to check hook state file.
        claude_sid=""
        if [ -d "$HOME/.claude/sessions" ]; then
            for check_pid in "$ai_pid" "$pid" $(pgrep -P "$pid" 2>/dev/null); do
                sf=$(grep -rl "\"pid\":$check_pid" "$HOME/.claude/sessions" 2>/dev/null | head -1)
                if [ -n "$sf" ]; then
                    claude_sid=$(python3 -c "
import json
try:
    print(json.load(open('$sf')).get('sessionId', ''))
except: pass
" 2>/dev/null)
                    [ -n "$claude_sid" ] && break
                fi
            done
        fi

        hook_state=""
        [ -n "$claude_sid" ] && hook_state=$(cat "$HOOK_STATE_DIR/$claude_sid" 2>/dev/null)

        if [ "$hook_state" = "running" ]; then
            running=$((running + 1))
        else
            last1=$(printf '%s\n' "$visible" | tail -1)
            last2=$(printf '%s\n' "$visible" | tail -2)
            last3=$(printf '%s\n' "$visible" | tail -3)
            if [ "$hook_state" = "asking" ]; then
                asking=$((asking + 1))
            elif printf '%s\n' "$last1" | grep -qi "enter to select\|esc to cancel"; then
                asking=$((asking + 1))
            elif printf '%s\n' "$last3" | grep -qE \
                '❯[[:space:]]+(Yes|No|Allow|Deny|Proceed|Cancel|Continue|Skip|Approve|y|n)|\[y/n\]|\[Y/n\]|\[y/N\]|Yes, and don'"'"'t ask'; then
                asking=$((asking + 1))
            elif [ -z "$hook_state" ] && printf '%s\n' "$last2" | grep -qi "esc to interrupt"; then
                running=$((running + 1))
            else
                waiting=$((waiting + 1))
            fi
        fi
    else
        # Gemini and others: braille spinner detection.
        last5=$(tmux capture-pane -t "$pane_id" -p -S -5 2>/dev/null)
        if printf '%s\n' "$last5" | grep -qE '^[[:space:]]*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏][[:space:]]'; then
            running=$((running + 1))
        elif printf '%s\n' "$visible" | grep -qE \
            '❯[[:space:]]+(Yes|No|Allow|Deny|Proceed|Cancel|Continue|Skip|Approve|y|n)|\[y/n\]|\[Y/n\]|\[y/N\]|Yes, and don'"'"'t ask'; then
            asking=$((asking + 1))
        else
            waiting=$((waiting + 1))
        fi
    fi

done < <(tmux list-panes -a \
    -F "#{pane_id} #{pane_pid} #{pane_current_command}" 2>/dev/null)

[ "$total" -eq 0 ] && exit 0

# Catppuccin colors via tmux style tags
BLUE="#[fg=#89b4fa]"
GREEN="#[fg=#a6e3a1]"
YELLOW="#[fg=#f9e2af]"
GRAY="#[fg=#6c7086]"
RESET="#[default]"

output="${BLUE}󱙺 ${total}${RESET}"
[ "$running" -gt 0 ] && output="${output}  ${GREEN}▶ ${running}${RESET}"
[ "$asking"   -gt 0 ] && output="${output}  ${YELLOW}? ${asking}${RESET}"
[ "$waiting"  -gt 0 ] && output="${output}  ${GRAY}○ ${waiting}${RESET}"

printf '%s' "$output"
