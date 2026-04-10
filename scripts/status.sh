#!/usr/bin/env bash
# status.sh — fast status bar component.
# Outputs a compact indicator like:  󱙺 3  ▶ 1  ◎ 2
# Returns nothing if no AI panes are found.

AI_PATTERN=$(tmux show-option -gqv @ai_status_processes 2>/dev/null)
AI_PATTERN="${AI_PATTERN:-claude|gemini}"

total=0
running=0
waiting=0

while IFS=' ' read -r pane_id pid cmd; do
    matched=0

    # Fast check: does pane_current_command match?
    if echo "$cmd" | grep -qiE "^($AI_PATTERN)$"; then
        matched=1
    else
        # Check pane_pid and its direct children (pane_pid is the shell;
        # the AI process is a child exec'd from there)
        for check_pid in "$pid" $(pgrep -P "$pid" 2>/dev/null); do
            cmdline=$(ps -o args= -p "$check_pid" 2>/dev/null) || continue
            if echo "$cmdline" | grep -qiE "(^|[/ ])($AI_PATTERN)"; then
                matched=1
                break
            fi
        done
    fi

    [ "$matched" -eq 0 ] && continue

    total=$((total + 1))

    content=$(tmux capture-pane -t "$pane_id" -p -S -4 2>/dev/null)
    if printf '%s' "$content" | grep -qP \
        '[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]|Thinking…|Working…|Running\b|◒|↓'; then
        running=$((running + 1))
    else
        waiting=$((waiting + 1))
    fi

done < <(tmux list-panes -a \
    -F "#{pane_id} #{pane_pid} #{pane_current_command}" 2>/dev/null)

[ "$total" -eq 0 ] && exit 0

# Catppuccin colors via tmux style tags
BLUE="#[fg=#89b4fa]"
GREEN="#[fg=#a6e3a1]"
YELLOW="#[fg=#f9e2af]"
RESET="#[default]"

output="${BLUE}󱙺 ${total}${RESET}"
[ "$running" -gt 0 ] && output="${output}  ${GREEN}▶ ${running}${RESET}"
[ "$waiting" -gt 0 ] && output="${output}  ${YELLOW}◎ ${waiting}${RESET}"

printf '%s' "$output"
