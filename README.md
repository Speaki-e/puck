# Puck

A macOS desktop pet that is also an AI agent. Two Swift apps:

- **Puck** — the pet: an always-on-top character that walks your screen, points
  at things, listens for voice, and drives the Mac (`run_shell`,
  `run_applescript`, click/find UI elements, launch apps).
- **PuckClient** — its window: chat, workspaces, git status, a native SwiftUI
  code editor, and a terminal pane.

The two talk over a local socket bridge. The agent core (chat, tools,
approvals, sessions) lives in `pet-app/Puck/Agent`.

## Build

```sh
sh pet-app/scripts/install.sh   # builds + signs both apps into /Applications
```

Needs Xcode, `xcodegen`, and an Apple Development certificate (a free personal
team is fine — a stable signature is what keeps the Accessibility grant alive
across rebuilds).

## Test

```sh
sh pet-app/scripts/test.sh   # PuckTests + a PuckClient build
```

Unattended, exits nonzero on any failure. Tests needing something this machine
may lack (`node`, a `claude`/`codex` CLI) skip rather than fail.

## Agent providers

Normal chat talks to the Anthropic or OpenAI API directly. The `code_editor`
tool instead runs a vendored ACP agent under `node`, which needs its vendor's
CLI (`claude` or `codex`) installed. Credentials go in Puck's `.env`:
`ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`, or `CODEX_API_KEY` /
`OPENAI_API_KEY`.

## Docs

- [`docs/decisions.md`](docs/decisions.md) — why the cross-cutting changes happened
- [`docs/verification.md`](docs/verification.md) — release criteria + manual desktop checks
- [`pet-app/design.md`](pet-app/design.md) — app design notes
