# chat-web

PuckClient's chat window UI (sidebar, top bar, transcript, input) -- React +
Tailwind v4 + shadcn/ui. Not an Electron app, not served over any network:
built to a static bundle and loaded by PuckClient via `WKWebView.loadFileURL`
(`pet-app/Puck/ClientWindow/ClientChatWebView.swift`). See
`../docs/decisions.md` (2026-08-13 entries) for why this exists as its own
package rather than living inside `../workspace`.

## Develop

```sh
pnpm install
pnpm dev
```

`pnpm dev` runs in a plain browser tab with no Swift on the other end -- a
dev-only mock bridge (`src/lib/dev-mock-bridge.ts`, stripped from production
builds via `import.meta.env.DEV`) feeds canned state so the UI is visible for
layout/style iteration without a full Xcode rebuild each time.

## Build

```sh
pnpm run build
```

Produces `dist/` as a classic (non-ES-module) script bundle -- WKWebView
refuses to execute `<script type="module">` under `file://`, see
`scripts/strip-module-script-tag.mjs` and `docs/decisions.md`. Not consumed
directly: `pet-app/scripts/sync-chat-web.sh` runs this and copies `dist/`
into `PuckClient/Resources/ChatWeb` before `xcodebuild`.

## Bridge

`src/lib/bridge-types.ts` is the JS-side mirror of
`pet-app/Puck/ClientWindow/ClientChatBridgeMessages.swift` -- kept in sync by
hand, not codegen'd. Swift pushes state via
`window.PuckChatBridge.receive(...)`; JS posts actions via
`window.webkit.messageHandlers.puckChat.postMessage(...)`
(`src/lib/puck-bridge.ts`). `src/state/chat-reducer.ts` folds pushes into UI
state and must not reimplement any decision Swift already made (e.g.
streaming append-vs-new-entry) -- Swift tells JS the answer explicitly
instead of JS re-deriving it.
