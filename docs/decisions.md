# Decisions log

Cross-cutting product/architecture decisions that don't belong inline in code
comments. Newest first. Each entry: what changed, why, and where the actual
implementation lives.

## 2026-08-13: PuckClient's chat UI is moving to web (React/Tailwind/shadcn)

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
