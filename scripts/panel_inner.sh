#!/usr/bin/env bash
# panel_inner.sh — runs inside the fzf popup.
# Writes the selected pane_id to $1 (tmpfile) on Enter/ctrl-right, nothing on escape.

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMPFILE="$1"

BLUE=$'\e[38;2;137;180;250m'
RESET=$'\e[0m'

LIST=$("$PLUGIN_DIR/scripts/panel_list.sh")

if [ -z "$LIST" ]; then
    printf '\n  No AI assistant panes found.\n\n'
    printf '  Detected pattern: %s\n\n' \
        "$(tmux show-option -gqv @ai_status_processes 2>/dev/null || echo 'claude|gemini')"
    printf '  (Press any key to close)\n'
    read -r -n 1
    exit 0
fi

HEADER="${BLUE}enter/ctrl-→${RESET}: jump   ${BLUE}ctrl-l${RESET}: preview mode   ${BLUE}ctrl-k${RESET}: list mode   ${BLUE}ctrl-r${RESET}: refresh   ${BLUE}esc/q${RESET}: close"

# Pick a random available port for fzf --listen
PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null)

# Background loop: every 3s reload list + refresh preview via fzf HTTP API
if [ -n "$PORT" ]; then
    (
        sleep 1
        while true; do
            curl -s -X POST "http://localhost:$PORT" \
                -d "reload(\"$PLUGIN_DIR/scripts/panel_list.sh\")" \
                >/dev/null 2>&1 || break
            curl -s -X POST "http://localhost:$PORT" \
                -d "refresh-preview" \
                >/dev/null 2>&1
            sleep 3
        done
    ) &
    REFRESH_PID=$!
    trap 'kill "$REFRESH_PID" 2>/dev/null' EXIT
    LISTEN_ARG="--listen=$PORT"
else
    LISTEN_ARG=""
fi

SELECTED=$(echo "$LIST" | fzf \
    --ansi \
    $LISTEN_ARG \
    --delimiter=$'\t' \
    --with-nth=2 \
    --prompt=" Assistants > " \
    --header="$HEADER" \
    --header-first \
    --preview='content=$(tmux capture-pane -t {1} -p 2>/dev/null | grep -v "^[[:space:]]*$"); [ -n "$content" ] && printf "%s\n" "$content" || printf "[pane {1} — no content captured]\n"' \
    --preview-window="right:55%:wrap:border-left" \
    --cycle \
    --bind='j:up,k:down' \
    --bind='ctrl-p:up,ctrl-n:down' \
    --bind="ctrl-r:reload(\"$PLUGIN_DIR/scripts/panel_list.sh\")" \
    --bind='ctrl-l:unbind(j)+unbind(k)+bind(j:preview-down)+bind(k:preview-up)' \
    --bind='ctrl-k:unbind(j)+unbind(k)+bind(j:up)+bind(k:down)' \
    --bind="ctrl-right:execute(echo {1} > \"$TMPFILE\")+abort" \
)

[ -z "$SELECTED" ] && exit 0

PANE_ID=$(echo "$SELECTED" | cut -d$'\t' -f1)
[ -n "$PANE_ID" ] && echo "$PANE_ID" > "$TMPFILE"
