# Socket protocol

Source of truth for the wire format: [`../src/types/events.ts`](../src/types/events.ts).
This document explains it; the types are normative.

## Transport

| | |
|---|---|
| Transport | Unix Domain Socket |
| Path | `~/Library/Application Support/PetAgent/bridge.sock` |
| Encoding | JSON Lines (newline-delimited JSON, UTF-8) |
| Server | pet-app (`NWListener`) |
| Client | workspace (Node `net`), reconnects with exponential backoff (1s -> 2s -> 4s, capped at 30s) |
| Common field | every message has a required `type` field |

## Disconnected behavior

While disconnected, pet-app runs as a plain pet with no agent features. If workspace's
agent tries to call a pet-app executor tool, it gets back an immediate
`{"ok":false,"error":"pet_app_disconnected"}` tool_result — no socket round trip needed.

## In-flight call semantics on disconnect

- **workspace**: the instant the socket drops, every tool_dispatch awaiting a reply has its
  Promise immediately rejected with `pet_app_disconnected`. If a tool_result for an
  already-cleaned-up id arrives after reconnect, it's ignored and only logged.
- **pet-app**: a tool that's already executing keeps running even if the connection drops.
  Failure to send the result back is logged and dropped — there's no retry, because the
  only recipient for that result is gone.

## Channels

### 1. Tool dispatch (workspace -> pet-app -> workspace)

```json
{"type":"tool_dispatch","id":"t1","tool":"launch_app","args":{"app_name":"Safari"}}
{"type":"tool_result","id":"t1","ok":true,"data":{"pid":501}}
{"type":"tool_result","id":"t1","ok":false,"error":"timeout"}
{"type":"tool_result","id":"t1","ok":false,"error":"execution_failed","detail":"zsh exited 127"}
{"type":"tool_cancel","id":"t1"}
```

- `id`: caller-generated string used to match a result to its dispatch.
- Default timeout is 15s, some tools raise it (see `timeout_sec` in
  [`../src/types/tools.ts`](../src/types/tools.ts)). The **sender**, not the receiver, is
  responsible for timing the call out.
- `tool_cancel` (workspace -> pet-app): abandon an in-flight dispatch — the user hit stop,
  or the agent run was aborted. pet-app cancels the handler and replies to the original
  `id` with `{"ok":false,"error":"cancelled"}`. Unknown or already-completed ids are
  ignored (idempotent).
- Standard `error` codes: `timeout`, `pet_app_disconnected`, `permission_denied`,
  `not_supported_target`, `execution_failed`, `unknown_tool` (tool isn't in the registry —
  a registry/agent mismatch, distinct from an execution failure), `cancelled` (abandoned
  via tool_cancel).
- `detail` (optional): human-readable failure specifics. `error` only ever carries a
  standard code, so the actual reason (a shell exit code, an exception message, ...) has
  to travel via `detail` to reach logs/debugging at all.
- `denied_by_user` (approval refused) never crosses this socket — approval happens inside
  ai-module before dispatch, so it only appears in the value ai-module reports back to the
  model (see `ToolResultErrorCode` in
  [`../src/types/agent-interface.ts`](../src/types/agent-interface.ts)).
- `tool_result.data`'s shape is tool-specific. Most tools return an object or `null`;
  `run_applescript` is the one exception and returns a bare string — see
  [`tools.md`](./tools.md) for the full per-tool response shape table.

### 2. State events (workspace -> pet-app, drives pet reactions)

```json
{"type":"event","event":"agent_thinking","workspace_id":"default","session_id":"default"}
{"type":"event","event":"text_chunk","text":"Running the test suite now...","workspace_id":"default","session_id":"default"}
{"type":"event","event":"tool_call","id":"t1","tool":"run_shell","args":{"command":"npm test"},"workspace_id":"default","session_id":"default"}
{"type":"event","event":"tool_call","id":"t2","tool":"code_editor","args":{"task":"fix the bug","project_path":"/tmp/x"},"detail":{"path":"src/main.ts"},"workspace_id":"default","session_id":"default"}
{"type":"event","event":"tool_result","id":"t1","ok":true,"data":{"stdout":"3 passed","stderr":"","exit_code":0},"workspace_id":"default","session_id":"default"}
{"type":"event","event":"await_approval","summary":"requesting to run rm -rf ./dist","approval_id":"a1","workspace_id":"w1","session_id":"s2"}
{"type":"event","event":"agent_done","ok":true,"summary":"3 tests passed","workspace_id":"default","session_id":"default"}
```

- `workspace_id`/`session_id` (2026-07-29) are on every event, not just `await_approval` —
  once more than one chat session can be open (channel 4), pet-app needs to know which
  session's timeline an incoming event belongs to, or it has no way to route
  `agent_thinking`/`tool_call`/`tool_result`/`agent_done` to the right one.
- `text_chunk`, and `tool_call`/`tool_result`'s `id`/`args`/`data`/`error`/`detail`
  (2026-07-29) exist because this stream now feeds two audiences, not just the pet's
  reactions — pet-app's F13 chat view needs a real timeline (streaming assistant text,
  which tool ran with what args, what it actually returned), effectively `AgentCallbacks`
  (see [`agent-interface.md`](./agent-interface.md)) proxied over the socket.
  - `tool_call.detail` is unchanged from its original purpose — a curated summary (e.g.
    code_editor's `{"path":...}`) used for the pet's jump-on-path-change reaction — and is
    distinct from `args` (the tool's actual raw call arguments, new).
  - `tool_call.id`/`tool_result.id` (both required) let the chat view correlate a call to
    its result, the same `tool_use` id `AgentCallbacks.onToolCallStart`/`onToolResult`
    already carry — parallel tool_use in one turn is exactly why this was needed there too.
  - `tool_result.data`/`error`/`detail` mirror `tool_result`'s dispatch-channel fields
    (channel 1) — same shapes, same standard error codes.
- `await_approval`'s `approval_id` additionally exists because the approval UI now lives in
  pet-app's client window rather than workspace's own renderer — resolving it has to
  round-trip this socket via `approval_response` (channel 6), so the event needs enough to
  route that response back to the right pending `resolve`.

### 3. User input (pet-app -> workspace)

```json
{"type":"user_input","text":"run this project's tests","source":"voice","workspace_id":"default","session_id":"default"}
{"type":"user_input","text":"look at this","source":"text","workspace_id":"w1","session_id":"s2","attachments":[{"type":"image","path":"/tmp/petagent-capture-1234.png"}]}
```

- `source`: `voice` | `text`
- `workspace_id`/`session_id` (2026-07-29, optional): default to `"default"` when omitted —
  existing single-workspace/single-session consumers are unaffected (see channel 4).
- `attachments` (2026-07-29, optional): images attached via pet-app's drag capture (F14).
  `path` is a local temp file on the same machine — not base64, to keep the socket message
  small.

### 4. Sessions and workspaces (2026-07-29)

pet-app's client window shows a sidebar with a workspace switcher and a per-workspace
chat session list. `workspace` still means a `code_editor` project_path unit; `session` is
one conversation under that workspace.

```json
{"type":"workspace_create_request","name":"cat house project","project_path":"/Users/x/cat-house"}
{"type":"workspace_create","workspace_id":"w2","name":"cat house project","project_path":"/Users/x/cat-house"}
{"type":"session_create_request","workspace_id":"w1","title":"new chat"}
{"type":"session_create","workspace_id":"w1","session_id":"s2","title":"fix the build error","origin":"agent"}
```

- Messages with a `_request` suffix are pet-app -> workspace; the confirming event without
  the suffix is workspace -> pet-app. The sidebar's "new chat"/"add workspace" buttons go
  through this round trip — workspace (ai-module) is the only source of truth for ids.
- `workspace_id: "default"` (no `project_path`) and, under it, `session_id: "default"` (the
  casual conversation) always exist implicitly from app start — no creation message needed.
- A workspace with no `project_path` (chat-only) is valid — `code_editor` and the editor view
  (channel 5) are unavailable for it.
- `session_create.origin`: `user` (created via the sidebar) | `agent` (the agent branched a
  casual conversation into a task session on its own judgement — see `onSessionCreated` in
  [`agent-interface.md`](./agent-interface.md) and plan/04_ai-module.md 3.7).

### 5. Editor view (2026-07-29)

The editor screen (file tree + Monaco) is now an embeddable web bundle workspace builds;
pet-app just loads it into a `WKWebView` (plan/02_pet-app.md F13, plan/03_workspace.md 4.7).
This traffic never crosses `bridge.sock` itself — it's high-frequency UI sync, unlike the
low-frequency pet-reaction events above, and pet-app relaying every byte would add nothing.
Instead workspace opens a per-workspace local loopback (127.0.0.1) HTTP+WebSocket server and
serves file tree/Monaco buffers/ACP progress directly to that webview.

```json
{"type":"editor_view_ready","workspace_id":"w1","url":"http://127.0.0.1:53912/editor"}
{"type":"editor_view_unavailable","workspace_id":"w1","reason":"no_project_path"}
```

- pet-app keeps the URL from this event and loads it into a `WKWebView` when the sidebar's
  editor button is clicked.
- The local server's lifecycle matches the workspace process (goes down when it does), fixed
  to 127.0.0.1 so it's never exposed externally.
- Running workspace standalone (pet-app disconnected) loads the same bundle into workspace's
  own fallback Electron shell instead (plan/03_workspace.md section 2, independence principle).

### 6. Approval response / run cancel (pet-app -> workspace, 2026-07-29)

The allow/deny approval UI and the chat's stop button now live in pet-app's client window
instead of workspace's renderer, so channel 2's `await_approval` needs a reply path:

```json
{"type":"approval_response","approval_id":"a1","approved":true}
{"type":"run_cancel","session_id":"s2"}
```

- `approval_response`: matched by `approval_id` to the `resolve(approved)` workspace is
  holding. Unknown/already-resolved ids are ignored (idempotent).
- `run_cancel`: aborts the `AbortSignal` behind the named session's in-flight `run()` — a
  different level from channel 1's `tool_cancel` (which abandons a single tool dispatch, not
  the whole conversation turn).
