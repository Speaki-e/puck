# Puck

Monorepo for the Puck project (desktop pet + single AI agent). Merged from five
previously separate repositories, each preserved as a subtree with full commit
history:

- `protocol` — shared contracts (socket schema, tool registry, module interfaces, avatar manifest)
- `pet-app` — the Puck (pet) and PuckClient (chat/agent) macOS apps
- `workspace` — the AI coding workspace (Electron + Monaco + ACP)
- `ai-module` — the single-agent core (Claude API tool-use loop)
- `landing` — the marketing/landing site

See `plan/` (separate repo, not part of this monorepo) for product specs.
