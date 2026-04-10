#!/usr/bin/env bash
# panel_list.sh — outputs the formatted fzf list for the AI panel.
# Called by panel_inner.sh for initial load, ctrl-r, and auto-refresh.

PLUGIN_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

GREEN=$'\e[38;2;166;227;161m'
YELLOW=$'\e[38;2;249;226;175m'
GRAY=$'\e[38;2;108;112;134m'
PEACH=$'\e[38;2;250;179;135m'
SKY=$'\e[38;2;137;220;235m'
DIM=$'\e[38;2;88;91;112m'
RESET=$'\e[0m'

CACHE="${HOME}/.cache/tmux-ai-status/panel-list"
mkdir -p "${HOME}/.cache/tmux-ai-status"
CACHE_TMP="${CACHE}.tmp.$$"
trap 'rm -f "$CACHE_TMP"' EXIT

"$PLUGIN_DIR/scripts/detect.sh" | awk -F'\t' \
    -v green="$GREEN" -v gray="$GRAY" -v yellow="$YELLOW" \
    -v peach="$PEACH" -v sky="$SKY" -v dim="$DIM" -v r="$RESET" '
{
    pane_id=$1; ai=$6; state=$7; summary=$8
    loc = $2 ":" $3 " [" $4 "." $5 "]"

    if (state == "running")     { s_icon = green  "▶" r; s_label = green  "running" r }
    else if (state == "asking") { s_icon = yellow "?" r; s_label = yellow "asking " r }
    else                        { s_icon = gray   "○" r; s_label = gray   "waiting" r }

    if (ai == "claude")      { t_icon = peach "◉" r; t_color = peach }
    else if (ai == "gemini") { t_icon = sky   "✧" r; t_color = sky   }
    else                     { t_icon = gray  "◦" r; t_color = gray  }

    t_label = t_color ai r

    summary_col = (summary != "") ? dim summary r : ""

    printf "%s\t%s %s  %s %-8s  %-22s  %s\n",
        pane_id, s_icon, s_label, t_icon, t_label, loc, summary_col
}' | tee "$CACHE_TMP"

# Only promote to stable cache if tee completed cleanly (not killed by SIGPIPE)
[ "${PIPESTATUS[2]}" -eq 0 ] && mv "$CACHE_TMP" "$CACHE"
