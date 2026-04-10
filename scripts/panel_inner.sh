#!/usr/bin/env bash
# panel_inner.sh — runs inside the fzf popup.
# Writes the selected pane_id to $1 (tmpfile) on Enter/ctrl-right, nothing on escape.

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMPFILE="$1"

# ── Catppuccin-aligned ANSI colors ──────────────────────────────────────────
BLUE=$'\e[38;2;137;180;250m'    # #89b4fa — label / blue
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

HEADER="${BLUE}enter/ctrl-→${RESET}: jump to pane   ${BLUE}ctrl-p/n${RESET}: up/down   ${BLUE}ctrl-r${RESET}: refresh   ${BLUE}esc/q${RESET}: close"

# Pick a random available port for fzf --listen
PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null)

# Background loop: every 3s reload list + refresh preview via fzf HTTP API
if [ -n "$PORT" ]; then
    (
        # Give fzf a moment to start listening
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
    --prompt=" Assistants › " \
    --header="$HEADER" \
    --header-first \
    --preview="tmux capture-pane -t {1} -p -e 2>/dev/null" \
    --preview-window="right:55%:wrap:border-left" \
    --cycle \
    --bind="ctrl-p:up,ctrl-n:down" \
    --bind="ctrl-r:reload(\"$PLUGIN_DIR/scripts/panel_list.sh\")" \
    --bind="ctrl-right:execute(echo {1} > \"$TMPFILE\")+abort" \
)

[ -z "$SELECTED" ] && exit 0

PANE_ID=$(echo "$SELECTED" | cut -d$'\t' -f1)
[ -n "$PANE_ID" ] && echo "$PANE_ID" > "$TMPFILE"
