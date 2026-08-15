# Puck

Monorepo for the Puck project (desktop pet + single AI agent). Two pieces:

- `pet-app` — the Puck (pet) and PuckClient (chat/agent/editor) macOS apps,
  including the agent core (F15). Everything the product does at runtime is
  here.
- `chat-web` — PuckClient's chat UI (React/Tailwind/shadcn), a static bundle
  PuckClient loads via `WKWebView.loadFileURL`.

## Building

```sh
cd pet-app
sh scripts/sync-chat-web.sh   # required: builds chat-web into PuckClient's
                              # resources, which are gitignored. Xcode has no
                              # idea chat-web exists, so this is a separate step
                              # and a fresh checkout will not build without it.
sh scripts/install.sh         # builds + signs both apps into /Applications
```

`landing` (the marketing/landing site) and `plan` (product specs) stay separate
repositories on purpose — not part of this monorepo.

## What used to be here

The repo was merged from four separate repositories, each preserved as a
subtree with full commit history. Three of them were deleted on 2026-08-15
once pet-app absorbed the last thing each still did; their history is still in
this repo's log, and the archived GitHub repositories are still read-only.

- `workspace` — the local code editor (Electron + Monaco + ACP). PuckClient's
  editor pane went native SwiftUI first, then took over the workspace registry
  and `code_editor`, at which point nothing was left for a second process to do.
- `protocol` — shared TypeScript contracts, plus the Swift mirrors pet-app
  copied. With no TypeScript consumer left there is no second implementation to
  hold a contract against; the Swift copies in `pet-app/Puck` are now the
  contract.
- `ai-module` — never built; superseded by pet-app's F15 agent.

## Node

Puck runs without Node. The one exception is the coding agent behind
`code_editor`: it is an ACP agent that runs under `node`, vendored as a single
bundled file by `pet-app/scripts/vendor-acp.sh`. Those bundles *are* committed,
so that script only needs running when bumping the pinned agent versions.

The agent also needs its vendor's CLI (`claude` or `codex`) installed — the ACP
packages are only shims around a ~256MB native binary, which is not vendored.
Without node or that CLI, `code_editor` reports why and nothing else in the app
is affected.

See [`docs/decisions.md`](docs/decisions.md) for the rationale behind
cross-cutting architecture changes.
