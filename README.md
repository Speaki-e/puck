# Puck

Monorepo for the Puck project (desktop pet + single AI agent). Merged from four
previously separate repositories (now archived on GitHub, read-only), each
preserved as a subtree with full commit history:

- `protocol` — shared contracts (socket schema, tool registry, module interfaces, avatar manifest)
- `pet-app` — the Puck (pet) and PuckClient (chat/agent) macOS apps, including the agent core (F15)
- `workspace` — the local code editor (Electron + Monaco + ACP), no longer an agent core
- `ai-module` — never built; superseded by pet-app's F15 agent, kept for its design record
- `chat-web` — PuckClient's chat UI (React/Tailwind/shadcn), a static bundle PuckClient loads via `WKWebView.loadFileURL`

`landing` (the marketing/landing site) and `plan` (product specs) stay separate
repositories on purpose — not part of this monorepo.

See [`docs/decisions.md`](docs/decisions.md) for the rationale behind
cross-cutting architecture changes.
