# Puck

Repository for the Puck project (desktop pet + single AI agent). One piece:

- `pet-app` — the Puck (pet) and PuckClient (chat/agent/editor) macOS apps,
  including the agent core (F15). All Swift.

## Building

```sh
cd pet-app
sh scripts/install.sh   # builds + signs both apps into /Applications
```

`landing` (the marketing/landing site) and `plan` (product specs) stay separate
repositories on purpose — not part of this monorepo.

## Testing

```sh
sh pet-app/scripts/test.sh   # the PuckTests suite + a PuckClient build
```

Runs unattended from anywhere and exits nonzero if either app fails to build or
any test fails. It runs the whole `PuckTests` target, then builds the separate
`PuckClient` scheme so its target membership and app entry point are covered.
Tests that need something this machine may not have (`node`, a `claude`/`codex`
CLI) skip rather than fail.

Release criteria and the required manual desktop checks are tracked in
[`docs/verification.md`](docs/verification.md).

## What used to be here

The repo was merged from four separate repositories, each preserved as a
subtree with full commit history. All of them were deleted on 2026-08-15 once
pet-app absorbed the last thing each still did; their history is still in this
repo's log, and the archived GitHub repositories are still read-only.

- `workspace` — the local code editor (Electron + Monaco + ACP). PuckClient's
  editor pane went native SwiftUI first, then took over the workspace registry
  and `code_editor`, at which point nothing was left for a second process to do.
- `protocol` — shared TypeScript contracts, plus the Swift mirrors pet-app
  copied. With no TypeScript consumer left there is no second implementation to
  hold a contract against; the Swift copies in `pet-app/Puck` are now the
  contract.
- `ai-module` — never built; superseded by pet-app's F15 agent.
- `chat-web` — PuckClient's chat UI (React/Tailwind/shadcn) in a WKWebView.
  Chosen to iterate quickly toward a bespoke shadcn look; once the target
  became stock Apple components, native SwiftUI was the faster way to get
  there and the web layer was pure cost. Its state always lived in
  `ClientWindowStore`, so removing it removed a mirror, not a model.

## Node

Puck runs without Node. The one exception is the coding agent behind
`code_editor`: it is an ACP agent that runs under `node`, vendored as a single
bundled file by `pet-app/scripts/vendor-acp.sh`. Those bundles *are* committed,
so that script only needs running when bumping the pinned agent versions.

The agent also needs its vendor's CLI (`claude` or `codex`) installed — the ACP
packages are only shims around a ~256MB native binary, which is not vendored.
Because the CLI runs with a private home directory, configure a stable
credential in Puck's `.env`: `ANTHROPIC_API_KEY` or a Claude Code setup-token
in `CLAUDE_CODE_OAUTH_TOKEN` for Claude, and `CODEX_API_KEY` or
`OPENAI_API_KEY` for Codex. Interactive CLI login files are not copied because
rotating a copied refresh token can invalidate the user's normal CLI login.
Without node, the CLI, or a usable credential, `code_editor` is unavailable;
normal chat is also unavailable when `AGENT_PROVIDER=cli` selects that CLI.

See [`docs/decisions.md`](docs/decisions.md) for the rationale behind
cross-cutting architecture changes.
