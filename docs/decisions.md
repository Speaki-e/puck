# Decisions log

Cross-cutting product/architecture decisions that don't belong inline in code
comments. Newest first. Each entry: what changed, why, and where the actual
implementation lives.

## 2026-08-14: PuckClient's editor pane goes native, drops workspace at runtime

Replaced `EditorWebView.swift` (a `WKWebView` loading a URL `workspace`
served over its own loopback `EditorGateway`, the entire compiled React/
Monaco bundle plus a WS file API) with a fully native SwiftUI file tree +
tabs + syntax-highlighted editor, backed directly by a new
`WorkspaceFileService` that reads/writes the project itself. Same motivation
as the chat window's earlier move, opposite direction: this time native
Swift is what let the app stop depending on `workspace` being launched at
all for manual file browsing/editing, not what was blocking it. Lightweight
by design -- no diff view, minimap, autocomplete/LSP, or multi-cursor,
matching Monaco's *un*used feature surface rather than its full one.

- New: `pet-app/Puck/ClientWindow/Editor/` -- `WorkspaceFileService.swift`
  (1:1 port of `workspace/src/main/file-service.ts`: tree listing with the
  same hardcoded ignore list, binary/UTF-8 sniffing, SHA-256-revision
  optimistic-concurrency save, image preview), `PathContainment.swift`/
  `ImageMime.swift` (ports of the matching `shared/*.ts`), `WorkspaceFileWatcher.swift`
  (FSEvents, not `DispatchSource` -- the latter doesn't recurse or notice new
  paths), `EditorPaneStore`/`EditorPaneStorePool` (tab/tree state, one
  `EditorPaneStore` per workspace, kept alive for the process's life same as
  the old `EditorWebViewPool`), `EditorAvailability.swift` (replaces
  `ClientWorkspace.editorViewURL`/`editorUnavailableReason` with a
  synchronous, locally-resolved enum -- no round trip needed now that
  PuckClient already has the real path before touching anything).
- Syntax highlighting: `CodeEditSourceEditor`/`CodeEditLanguages`
  (MIT, tree-sitter-based, the actual editor component behind CodeEdit.app),
  the first external SwiftPM dependency in this repo (`project.yml`'s new
  `packages:` section). `STTextView` was ruled out (GPLv3/paid-commercial
  license); `Runestone` was ruled out (its own README says AppKit/Catalyst
  support isn't finished). Its bundled `SwiftLint` build-tool plugin has no
  local binary to run in this environment, so builds/tests pass
  `-skipPackagePluginValidation` now (`scripts/install.sh` updated to match)
  -- harmless, since that plugin only lints `CodeEditSourceEditor`'s own
  source, not this repo's.
- `read_file`/`open_in_editor` re-pointed to native too, in the same pass:
  new `Puck/Agent/EditorFileDelegate.swift`, delegated from `AgentRunner`
  exactly like `code_editor` already was (`AgentFileDelegation` closures,
  offered to the model only when wired) -- **not** `.petApp`-executor
  `ToolExecutor`/`ToolHandler` dispatch, since that machinery runs in
  Puck.app's separate process/on Puck.app's own state, which has no access
  to PuckClient's editor-pane state at all. Both tools were actually inert
  before this (excluded from `AgentRunner.petToolSpecs` and never delegated),
  so this is the first time either is reachable by the model, closing a real
  inconsistency: previously a human could edit files with `workspace` fully
  unlaunched but the agent couldn't read one at all.
- `pet-app/project.yml`'s `packages:`/target `dependencies:` had to go on
  **both** `Puck` and `PuckClient` targets, not just `PuckClient` -- the new
  `Editor/` sources live under the already-shared `Puck/ClientWindow` path,
  so `Puck.app` (the pet, no editor UI of its own) links
  `CodeEditSourceEditor` transitively too, same structural situation as it
  already linking WebKit for the same reason.
- Explicitly not touched: `workspace`'s TypeScript side (`EditorGateway`,
  `editor_view_ready`/`editor_view_unavailable` sending) -- PuckClient just
  stops consuming those messages; `EditorGateway` becomes a dead-consumer
  server that still starts on every `workspace` launch, a natural TS-side
  cleanup follow-up, not bundled here. `code_editor`'s ACP-subprocess
  mechanism (still genuinely needs `workspace` running) is untouched.
- Verified: 1016/1016 `PuckTests` (was 957 pre-Electron-revert baseline +
  59 new, covering `WorkspaceFileService`/`PathContainment`/`EditorLanguage`/
  `WorkspaceFileWatcher`/`EditorPaneStore`/`EditorFileDelegate`/
  `AgentRunner.pathArgument`), both `Puck`/`PuckClient` targets build clean,
  `scripts/install.sh` builds+signs+installs both apps.

## 2026-08-13: PuckClient's chat UI moved to web (React/Tailwind/shadcn) -- done

Landed in full: `chat-web/` (sidebar, top bar, transcript, streaming, tool
calls, approvals, session/workspace switching) replaces
`ChatView.swift`/`ClientSidebarView.swift`, which are deleted.
`ClientChatBridge.swift`/`ClientChatBridgeMessages.swift` are the JS↔Swift
bridge (`chat-web/src/lib/bridge-types.ts` mirrors the Swift side by hand).
`ClientWindowStore`/`ChatSession` are unchanged -- `AppDelegate.swift` now
routes chat events through `chatBridge.applyEvent(...)` (which folds into the
store itself, then pushes the exact delta) instead of calling
`ClientWindowStore.handleChatEvent` directly, and pushes a blanket
`refreshWorkspacesAndSessions()` after every other store mutation (new
workspace/session, editor URL, task-session moves) -- the store isn't
Combine-observed because its session list (`sessionOrder`/`sessionsByKey`)
isn't `@Published`, only individual fields like `workspaces` are, so passive
observation would silently miss session-list changes. `AgentSettingsView`
(API key entry) stays native, opened the same way via
`NSApp.sendAction(Selector(("showSettings:")))`, now triggered by
`action:openSettings` from the web sidebar instead of a SwiftUI button.
Editor-open state moved from `ClientWindowView`'s local `@State` to
`ClientChatBridge` (`isEditorOpen` + `setEditorOpenChangeHandler`), since the
toggle now lives in the web sidebar but still has to drive the native
`HSplitView` layout choice. Verified end-to-end via the accessibility tree
(not screenshots) after a real `state:hydrate` round-trip through the actual
`ClientWindowStore` -- 957/957 `PuckTests` still pass.

### (original scoping notes, kept for context)

Native SwiftUI iteration on PuckClient's chat window couldn't hit a specific
visual target (Orca/Zed-inspired, minimalist, shadcn) at any reasonable
speed -- no devtools, no hot reload, no exact-value extraction, just
rebuild/relaunch/eyeball-compare. `workspace`'s own renderer (already
Tailwind+shadcn) took a rich shadcn migration far more easily for the same
reason. Full plan: `puck/pet-app` chat/sidebar/settings gets rebuilt as a new
standalone package, `puck/chat-web/` (React+Tailwind+shadcn, its own
`package.json`, not part of `workspace`'s pnpm workspace or build pipeline --
routing it through `workspace` would partially reverse the entry right below
this one, and concretely break chat for the default project-less workspace
since `EditorGateway` never starts without a bound project). Built to a
static bundle, copied into `PuckClient.app`'s resources
(`PuckClient/Resources/ChatWeb`, synced by `pet-app/scripts/sync-chat-web.sh`),
loaded via `WKWebView.loadFileURL` (`ClientChatWebView.swift`) and driven by a
native JS↔Swift bridge -- `ClientWindowStore`/`ChatSession` stay the real-time
source of truth exactly as they are today, they just gain a second UI
consumer. Full design in `.claude/plans/optimized-mapping-curry.md` (local to
byeolki's machine, not committed) -- ported here as work lands.

**`file://` + WKWebView gotchas found empirically (Phase 0 spike), matter for
any future static bundle loaded this way**:
- WKWebView silently refuses to execute `<script type="module">` under
  `file://` -- navigation succeeds, no error surfaces anywhere (not
  `WKNavigationDelegate`, not `window.onerror`), the script just never runs.
  Fix: build as a classic (non-module) bundle. Vite's `rollupOptions.output`
  `{format: "iife", inlineDynamicImports: true}` does this, but Vite's HTML
  plugin still hardcodes `type="module" crossorigin` on the injected
  `<script>` tag regardless of the actual output format -- a postbuild step
  has to rewrite it (`chat-web/scripts/strip-module-script-tag.mjs`).
- That rewritten tag must keep `defer` (not become a bare classic script):
  `type="module"` scripts execute after the document parses, and dropping
  that guarantee makes `document.getElementById("root")` run before `<body>`
  exists, which is React error #299 ("target container is not a DOM
  element"), not any kind of loading failure.
- When a script has no `crossorigin`/CORS attributes (which this one now
  doesn't, by necessity), WKWebView reports any runtime error inside it as a
  bare `"Script error."` with no file/line/message -- by design, not a bug.
  Debugging needs errors caught and logged explicitly from inside the bundle
  (`try/catch` around the entry point, `console.error` the real
  `error.message`/`error.stack`) rather than relying on `window.onerror`.

## 2026-08-13: workspace trimmed to editor-only UI

workspace is embedded in PuckClient purely as the `code_editor` view (WKWebView),
so surfaces that duplicated PuckClient's own chat/settings were dead weight --
one, `CommandDock`'s agent input, was actively broken there:
`gateway-workspace-api.ts`'s `runCommand` just threw
("Editor View에서는 에이전트 명령을 직접 실행하지 않습니다").

- Removed: `CommandDock` (replaced by a minimal read-only status strip),
  `WorkspaceTitlebar`'s "Workspace ALPHA" brand chrome (redundant inside
  another app's window), `SettingsPanel`'s "모델" field (nothing has consumed
  `WorkspaceSettings.model` since ai-module was retired).
- Kept: the API key field (still the one non-env-var way to hand ACP a Claude
  key), file-size-limit/log-level/recent-projects (still workspace's own
  domain) -- these weren't in scope, just the agent-brain duplication was.
- Backing IPC (`agent:run`/`agent:cancel`, `WorkspaceController.setAgentCommands`)
  removed to match; `agent:status`/`agent:working-paths` kept (still real ACP
  readiness feedback).

## 2026-08-13: one point color across workspace and pet-app -- pumpkin orange

workspace's accent had drifted to blue (`#3291ff`) while pet-app's ClientPalette
used orange (`#ed8c33`), so the two apps' UIs no longer matched even though
PuckClient embeds workspace's editor directly. Unified on pet-app's existing
orange rather than workspace's blue, since orange was already the app's brand
color (see the removed "Figma color matching" scope note in `pet-app/design.md`).

- workspace: `src/renderer/styles.css`'s `--blue`/`--blue-soft` renamed to
  `--brand`/`--brand-soft` and repointed to `#ed8c33`; the handful of
  hardcoded blue rgba/hex tints (focus rings, status-pulse glow) converted to
  the same orange.
- pet-app: `ClientPalette.light/.dark/.glass` all now use the identical
  `#ed8c33` accent (previously `.dark` alone had drifted to workspace's blue).

## 2026-08-12: workspace becomes a plain editor; pet-app's F15 brain is permanent

pet-app's temporary F15 agent core (`Puck/Agent/AgentRunner.swift`, Swift +
OpenAI) is now the single, permanent decision-maker for all user commands.
ai-module was never started, so instead of building it and retiring F15, we
retired the ai-module design and kept F15. workspace no longer judges "what
kind of request is this" — it only executes `code_editor` once, for whatever
text pet-app's CodeEditorDelegate already decided is a coding task.

- Implementation: `workspace/src/agent-host/direct-code-editor-runtime.ts`
  (`DirectCodeEditorRuntime`), wired in `workspace/src/agent-host/agent-runner.ts`.
- Removed: `AiModuleRuntime`, `MockAgentRuntime`, `petAppProxy`, the
  `--direct-code-editor`/`--mock-ai` flags, the `runtime_config_request` RPC.
- Delegation path: pet-app's `CodeEditorDelegate.execute` sends the existing
  `user_input`/`agent_done` socket messages (no protocol change needed) rather
  than a new `tool_dispatch` direction.
- Details: `workspace/docs/architecture.md` "AI 실행 경계"; plan repo
  `02_pet-app.md` F15, `프로젝트_개요.md` §2.

## 2026-08-12: PuckClient adopts workspace's design, not the other way around

Earlier the client window's `ClientPalette`/`ClientTheme` were pushed toward a
Figma reference and workspace's renderer theme was pulled to match *that*.
This reversed: workspace's actual shadcn theme (blue `#3291ff` accent,
`#090909`/`#111111` surfaces, 12px/6px corner radii) is now the source of
truth, and pet-app's `ClientPalette.dark`/`ClientTheme` were ported to match
it pixel-for-pixel. The client window's default size also grew to 1440x900
(from 1100x740) since the sidebar + file tree + Monaco + chat compete for
width once the embedded editor pane is open.

## 2026-08-12: repo consolidation

`protocol`, `pet-app`, `workspace`, `ai-module` merged into one monorepo,
[Speaki-e/puck](https://github.com/Speaki-e/puck) (git subtree, history
preserved). The four standalone repos are archived on GitHub (read-only).
`landing` and `plan` (spec repo) stay separate on purpose. See plan repo
`프로젝트_개요.md` for the up-to-date system/team tables.
