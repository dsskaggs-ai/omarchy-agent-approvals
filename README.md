# omarchy-agent-approvals

A flashing bar light for [Omarchy](https://omarchy.org) (Quickshell-based) that turns on the moment **any** AI agent on the machine is waiting on a human — Hermes (Telegram, Buzz, CLI), Claude Code, Codex, and any terminal-based agent running under [herdr](https://herdr.dev) or tmux.

One light for every agent. No workspace-hopping to notice a stalled approval.

- **Idle** — small dim dot, no attention drawn.
- **Pending** — hard red/amber flash with a count badge, visible on every workspace.
- **Left-click** — jump to the oldest pending agent (focuses its herdr/tmux pane or the relevant app window) and fire a desktop notification.
- **Right-click** — clear every pending record (and close any toasts that opened for them).
- **Middle-click** — force an immediate rescan.

## Install

```bash
omarchy plugin add https://github.com/dsskaggs-ai/omarchy-agent-approvals.git --enable
```

This also needs the CLI + scanner on your `$PATH` (the plugin shells out to them):

```bash
git clone https://github.com/dsskaggs-ai/omarchy-agent-approvals.git /tmp/agent-approvals
install -m 755 /tmp/agent-approvals/agent-approval /tmp/agent-approvals/agent-approval-scan \
  /tmp/agent-approvals/hermes-approval-hook ~/.local/bin/
```

## How it works

Every source is decoupled — anything that can run a shell can light the bar:

```bash
agent-approval add <source> <id> "Title" "detail"   # light on
agent-approval clear <source> <id>                   # light off (closes any tracked toast too)
```

State lives in `~/.local/state/omarchy/approvals/<source>__<id>.json`; the widget polls that
directory and reconciles herdr/tmux state every few seconds via `agent-approval-scan`.

### Wiring a source

| Source | How |
|---|---|
| **Hermes** | `hooks.pre_approval_request` / `hooks.post_approval_response` in your profile's `config.yaml`, pointed at `hermes-approval-hook`. Allowlist it once with `hermes hooks doctor` (interactive) or seed `shell-hooks-allowlist.json` directly for headless profiles. |
| **Claude Code** | Add a `Notification` hook (sets the light) and `PostToolUse`/`Stop`/`UserPromptSubmit`/`SessionEnd` hooks (clear it) in `~/.claude/settings.json`, each calling `agent-approval claude-hook`. |
| **Codex** | `notify = ["/path/to/agent-approval", "codex-notify"]` at the top level of `~/.codex/config.toml`. |
| **herdr / tmux** | Nothing to configure — `agent-approval-scan` polls herdr's native `blocked` pane state and falls back to a regex scan of recent pane text for agents herdr doesn't classify yet. |
| **Anything else** | Call `agent-approval add`/`clear` directly from your own script/hook. |

## Why toasts actually close

Omarchy's notification service only removes a *visible* popup (and archives its state file)
through its own `dismissPopup()` — the raw freedesktop `CloseNotification` D-Bus call never
reaches that code path, so a naively-closed toast just sits there until its own timer expires.
This plugin's CLI dismisses through Omarchy's own IPC target instead
(`omarchy-shell notifications dismiss <title>`), so clearing the bar light reliably closes the
toast with it.

## Requirements

- `jq`, `notify-send`, `gdbus` (all standard on Omarchy)
- Optional: [herdr](https://herdr.dev) and/or `tmux` for terminal-agent detection
- Optional: Hermes / Claude Code / Codex, wired per the table above

## License

MIT
