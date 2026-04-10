#!/usr/bin/env bash
# panel_inner.sh — fzf agent list inside the popup.
# enter: write pane_id and close popup (jump to that pane).

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMPFILE="$1"

BLUE=$'\e[38;2;137;180;250m'
RESET=$'\e[0m'

HEADER="${BLUE}enter${RESET}: jump   ${BLUE}ctrl-r${RESET}: refresh   ${BLUE}esc/q${RESET}: close"

CACHE="${HOME}/.cache/tmux-ai-status/panel-list"

PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null)

if [ -n "$PORT" ]; then
    (
        sleep 1
        while true; do
            curl -s -X POST "http://localhost:$PORT" \
                -d "reload(\"$PLUGIN_DIR/scripts/panel_list.sh\")" \
                >/dev/null 2>&1 || break
            sleep 3
        done
    ) &
    REFRESH_PID=$!
    trap 'kill "$REFRESH_PID" 2>/dev/null' EXIT
    LISTEN_ARG="--listen=$PORT"
else
    LISTEN_ARG=""
fi

# Use cache as initial input (instant open); background loop refreshes live data.
if [ -f "$CACHE" ]; then
    LIST_SOURCE=(cat "$CACHE")
else
    LIST_SOURCE=("$PLUGIN_DIR/scripts/panel_list.sh")
fi

SELECTED=$("${LIST_SOURCE[@]}" | fzf \
    --ansi \
    $LISTEN_ARG \
    --delimiter=$'\t' \
    --with-nth=2 \
    --prompt=" Assistants > " \
    --header="$HEADER" \
    --header-first \
    --preview='while :; do printf "\033[H\033[2J"; tmux capture-pane -t {1} -p -e 2>/dev/null | tail -n "$FZF_PREVIEW_LINES"; sleep 0.2; done' \
    --preview-window="right:55%:wrap:border-left:noinfo" \
    --cycle \
    --bind='j:up,k:down' \
    --bind='ctrl-p:up,ctrl-n:down' \
    --bind="ctrl-r:reload(\"$PLUGIN_DIR/scripts/panel_list.sh\")" \
)

[ -z "$SELECTED" ] && exit 0

PANE_ID=$(printf '%s' "$SELECTED" | cut -d$'\t' -f1)
[ -n "$PANE_ID" ] && printf '%s' "$PANE_ID" > "$TMPFILE"
