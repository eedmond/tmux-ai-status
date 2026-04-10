#!/usr/bin/env bash
# panel_inner.sh — runs inside the fzf popup.
# Writes the chosen action + pane_id to $1 (tmpfile) before exiting.

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMPFILE="$1"

# ── Catppuccin-aligned ANSI colors ──────────────────────────────────────────
GREEN=$'\e[38;2;166;227;161m'   # #a6e3a1 — running
YELLOW=$'\e[38;2;249;226;175m'  # #f9e2af — waiting
GRAY=$'\e[38;2;108;112;134m'    # #6c7086 — idle
BLUE=$'\e[38;2;137;180;250m'    # #89b4fa — label
RESET=$'\e[0m'

format_list() {
    "$PLUGIN_DIR/scripts/detect.sh" | awk -F'\t' -v g="$GREEN" -v y="$YELLOW" \
        -v gr="$GRAY" -v b="$BLUE" -v r="$RESET" '
    {
        if ($7 == "running")       { icon = g "▶ running" r }
        else if ($7 == "waiting")  { icon = y "◎ waiting" r }
        else                       { icon = gr "○ idle   " r }

        ai   = b $6 r
        loc  = $2 ":" $3 " [" $4 "." $5 "]"
        printf "%s\t%s  %-16s  %-10s  %s\n", $1, icon, ai, loc, $1
    }'
}

LIST=$(format_list)

if [ -z "$LIST" ]; then
    printf '\n  No AI assistant panes found.\n\n'
    printf '  Detected pattern: %s\n\n' \
        "$(tmux show-option -gqv @ai_status_processes 2>/dev/null || echo 'claude|gemini')"
    printf '  (Press any key to close)\n'
    read -r -n 1
    exit 0
fi

HEADER="${BLUE}enter${RESET}: jump   ${BLUE}ctrl-o${RESET}: open in popup   ${BLUE}ctrl-p/n${RESET}: up/down   ${BLUE}ctrl-r${RESET}: refresh"

RESULT=$(echo "$LIST" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=2 \
    --prompt=" Assistants › " \
    --header="$HEADER" \
    --header-first \
    --preview="tmux capture-pane -t \$(echo {1}) -p -S -50 2>/dev/null" \
    --preview-window="right:55%:wrap:border-left" \
    --expect="ctrl-o,ctrl-r" \
    --bind="ctrl-p:up,ctrl-n:down" \
    --bind="ctrl-r:reload(\"$PLUGIN_DIR/scripts/detect.sh\" | awk -F'\t' \
        '{if(\$7==\"running\") icon=\"▶ running\"; \
          else if(\$7==\"waiting\") icon=\"◎ waiting\"; \
          else icon=\"○ idle   \"; \
          printf \"%s\t%s  %-16s  %-10s  %s\n\",\$1,icon,\$6,\$2\":\"$3\" [\"$4\".\"$5\"]\",\$1}')" \
)

[ -z "$RESULT" ] && exit 0

KEY=$(echo "$RESULT" | head -1)
SELECTED=$(echo "$RESULT" | sed -n '2p')
PANE_ID=$(echo "$SELECTED" | cut -d$'\t' -f1)

[ -z "$PANE_ID" ] && exit 0

if [ "$KEY" = "ctrl-o" ]; then
    echo "popup" > "$TMPFILE"
else
    echo "jump"  > "$TMPFILE"
fi
echo "$PANE_ID" >> "$TMPFILE"
