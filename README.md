# tmux-ai-status

A tmux plugin that tracks AI coding assistants (Claude Code, Gemini CLI, and others) running across your tmux sessions. It adds a status bar indicator showing how many assistants are active and what they're doing, plus a quick-access panel for navigating between them.

## What it does

**Status bar indicator** — appended to `status-right`, refreshes every 5 seconds:

```
󱙺 3  ▶ 1  ? 1  ○ 1
```

| Symbol | Meaning |
|--------|---------|
| `󱙺 N` | N total AI assistant panes detected |
| `▶ N` | N actively running (processing a request) |
| `? N` | N waiting for your input (permission prompt, yes/no question) |
| `○ N` | N idle (waiting for your next prompt) |

**Agent panel** (`<prefix> + Ctrl-a`) — a full-width popup with:
- Left: fzf list of all detected assistant panes, with name, session, and current state
- Right: live preview of the selected pane's output, updated every 200ms

```
╭─────────────────────────────────────────────────────────────────────────────╮
│  AI Assistants                                                              │
│  enter: jump   ctrl-r: refresh   esc/q: close                              │
│ ▶ running  ◉ claude  main:editor [1.2]   Refactoring auth module    │ ...  │
│ ○ waiting  ◉ claude  work:api    [2.1]   Add rate limiting           │ ...  │
│ ▶ running  ✧ gemini  main:tests  [1.3]                               │ ...  │
╰─────────────────────────────────────────────────────────────────────────────╯
```

### Panel keybindings

| Key | Action |
|-----|--------|
| `enter` | Jump to selected pane |
| `ctrl-r` | Manually refresh the list |
| `j` / `k` | Navigate down / up |
| `ctrl-n` / `ctrl-p` | Navigate down / up (alternative) |
| `esc` / `q` | Close panel, return to original window |

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/eedmond/tmux-ai-status ~/.tmux/plugins/tmux-ai-status
```

Or for local development, clone anywhere and reference the path directly.

### 2. Load the plugin in `.tmux.conf`

**Option A — direct path** (recommended for local dev):
```tmux
run-shell "$HOME/.tmux/plugins/tmux-ai-status/tmux-ai-status.tmux"
```

**Option B — via TPM**:
```tmux
set -g @plugin 'eedmond/tmux-ai-status'
run '~/.tmux/plugins/tpm/tpm'
```

### 3. Reload tmux config

```bash
tmux source ~/.tmux.conf
```

### 4. (Optional but recommended) Configure Claude Code hooks

Without hooks, Claude state detection falls back to parsing pane content, which is less reliable. With hooks, state updates are instant and accurate.

Add the following to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-ai-status/scripts/hook.sh UserPromptSubmit"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-ai-status/scripts/hook.sh PreToolUse"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-ai-status/scripts/hook.sh Stop"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.tmux/plugins/tmux-ai-status/scripts/hook.sh Notification"
          }
        ]
      }
    ]
  }
}
```

Adjust the path to `hook.sh` if you installed to a different location.

## Configuration

All options are set in `.tmux.conf` before loading the plugin.

### Custom process pattern

Control which processes are detected as AI assistants. The value is a case-insensitive `|`-separated regex alternation matched against process names and command lines.

```tmux
set -g @ai_status_processes "claude|gemini|aider|llm"
```

Default: `claude|gemini`

### Status bar

The plugin appends its indicator to `status-right` automatically. If you manage `status-right` manually, you can embed the component yourself and skip the auto-append by setting `status-right` *after* the plugin loads:

```tmux
run-shell "~/.tmux/plugins/tmux-ai-status/tmux-ai-status.tmux"
set -g status-right "#(~/.tmux/plugins/tmux-ai-status/scripts/status.sh)  #H"
```

### Status interval

The plugin sets `status-interval 5` if your current interval is unset, 0, or greater than 5. Override after loading if you want a different value:

```tmux
set -g status-interval 2
```

## Requirements

- tmux 3.2+ (for `display-popup`)
- fzf 0.38+ (for `--listen` and event bindings; tested on 0.71)
- bash 4+
- python3 (for JSON parsing in hook and detect scripts)
- curl (for fzf `--listen` background refresh)

## File structure

```
tmux-ai-status.tmux       # TPM entry point — sets keybinding and status-right
scripts/
  status.sh               # Fast status bar component (runs every status-interval seconds)
  detect.sh               # Full pane scanner — outputs TSV of AI panes with state
  hook.sh                 # Claude Code hook handler — writes state files, warms cache
  panel.sh                # Panel launcher — creates popup, handles pre/post navigation
  panel_inner.sh          # fzf list inside the popup, reads cache, manages live refresh
  panel_list.sh           # Formats detect.sh output for fzf, writes cache atomically
  panel_bg.sh             # Helper for background window switching (legacy)
  panel_preview.sh        # Standalone preview loop (legacy)
```

## How it works

### Detection

`detect.sh` (and the lighter `status.sh`) scan all tmux panes with `tmux list-panes -a`. For each pane it checks whether the pane's current command — or any direct child process — matches the configured AI process pattern (default: `claude|gemini`). This covers both cases: AI tools run directly as the pane command, and tools launched from a shell (e.g. running `claude` inside a `zsh` pane).

### State detection

Knowing *what* an assistant is doing (running vs. asking vs. waiting) requires more than process detection:

**For Claude Code** — the most accurate source is a hook state file. When Claude Code hooks are configured (see below), `hook.sh` writes a state file (`running`, `asking`, or `waiting`) on every hook event. `detect.sh` reads this file by matching the pane's PID to a Claude session ID, then reading the corresponding state file from `$TMPDIR/claude-tmux-state/`. This gives real-time accuracy.

Without hooks, the plugin falls back to pane content inspection — looking for "esc to interrupt" (running), permission prompts and yes/no questions (asking), or nothing active (waiting).

**For Gemini and others** — braille spinner characters (`⠋⠙⠹…`) in recent pane output indicate active processing. Permission prompts are detected the same way as Claude.

### Panel caching

The panel list is cached at `~/.cache/tmux-ai-status/panel-list`. On open, the cached list is shown immediately while a background refresh runs. The cache is written atomically (via a temp file + `mv`) so a partially-loaded panel that gets closed never corrupts it. The hook handler also warms the cache in the background on every Claude state change, so the panel is pre-populated before you even open it.

