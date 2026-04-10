#!/usr/bin/env bash
# panel_inner.sh — runs inside the fzf popup.
# Writes the selected pane_id to $1 (tmpfile) on Enter, nothing on escape.

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
TMPFILE="$1"

# ── Catppuccin-aligned ANSI colors ──────────────────────────────────────────
GREEN=$'\e[38;2;166;227;161m'   # #a6e3a1 — running
YELLOW=$'\e[38;2;249;226;175m'  # #f9e2af — asking
GRAY=$'\e[38;2;108;112;134m'    # #6c7086 — idle
BLUE=$'\e[38;2;137;180;250m'    # #89b4fa — label / claude icon
PEACH=$'\e[38;2;250;179;135m'   # #fab387 — claude
SKY=$'\e[38;2;137;220;235m'     # #89dceb — gemini
DIM=$'\e[38;2;88;91;112m'       # #585b70 — summary text
RESET=$'\e[0m'

# Per-tool icon and color
tool_icon() {
    case "$1" in
        claude) printf '%s◉%s' "$PEACH" "$RESET" ;;
        gemini) printf '%s✧%s' "$SKY"   "$RESET" ;;
        *)      printf '%s◦%s' "$GRAY"  "$RESET" ;;
    esac
}

tool_color() {
    case "$1" in
        claude) printf '%s' "$PEACH" ;;
        gemini) printf '%s' "$SKY"   ;;
        *)      printf '%s' "$GRAY"  ;;
    esac
}

format_list() {
    "$PLUGIN_DIR/scripts/detect.sh" | awk -F'\t' \
        -v green="$GREEN" -v gray="$GRAY" -v yellow="$YELLOW" \
        -v peach="$PEACH" -v sky="$SKY" -v dim="$DIM" -v r="$RESET" '
    {
        pane_id=$1; ai=$6; state=$7; summary=$8
        loc = $2 ":" $3 " [" $4 "." $5 "]"

        if (state == "running")  { s_icon = green "▶" r; s_label = green "running" r }
        else if (state == "asking") { s_icon = yellow "?" r; s_label = yellow "asking " r }
        else                     { s_icon = gray  "○" r; s_label = gray  "idle   " r }

        if (ai == "claude")      { t_icon = peach "◉" r; t_color = peach }
        else if (ai == "gemini") { t_icon = sky   "✧" r; t_color = sky   }
        else                     { t_icon = gray  "◦" r; t_color = gray  }

        t_label = t_color ai r

        summary_col = (summary != "") ? dim summary r : ""

        printf "%s\t%s %s  %s %-8s  %-22s  %s\n",
            pane_id, s_icon, s_label, t_icon, t_label, loc, summary_col
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

HEADER="${BLUE}enter${RESET}: jump to pane   ${BLUE}ctrl-p/n${RESET}: up/down   ${BLUE}ctrl-r${RESET}: refresh   ${BLUE}esc/q${RESET}: close"

SELECTED=$(echo "$LIST" | fzf \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=2 \
    --prompt=" Assistants › " \
    --header="$HEADER" \
    --header-first \
    --preview="tmux capture-pane -t {1} -p -S -50 2>/dev/null" \
    --preview-window="right:55%:wrap:border-left" \
    --cycle \
    --bind="ctrl-p:up,ctrl-n:down" \
    --bind="ctrl-r:reload(\"$PLUGIN_DIR/scripts/detect.sh\" | awk -F'\t' \
        -v r=\"$RESET\" -v g=\"$GREEN\" -v gr=\"$GRAY\" \
        -v p=\"$PEACH\" -v s=\"$SKY\" -v d=\"$DIM\" \
        '{st=(\$7==\"running\") ? g\"▶\"r\" \"g\"running\"r : gr\"○\"r\" \"gr\"idle   \"r; \
          ti=(\$6==\"claude\") ? p\"◉\"r : (\$6==\"gemini\") ? s\"✧\"r : gr\"◦\"r; \
          tc=(\$6==\"claude\") ? p : (\$6==\"gemini\") ? s : gr; \
          sm=(\$8!=\"\") ? d\$8 r : \"\"; \
          printf \"%s\t%s %s  %s %-8s  %-22s  %s\n\",\$1,ti,st,ti,tc\$6 r,\$2\":\"\$3\" [\"$4\".\"$5\"]\",sm}')" \
)

[ -z "$SELECTED" ] && exit 0

PANE_ID=$(echo "$SELECTED" | cut -d$'\t' -f1)
[ -n "$PANE_ID" ] && echo "$PANE_ID" > "$TMPFILE"
