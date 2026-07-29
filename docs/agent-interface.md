# ai-module interface

Source of truth: [`../src/types/agent-interface.ts`](../src/types/agent-interface.ts).
This document explains it; the types are normative.

```typescript
run(command: string, sessionId: string, context: Context, callbacks: AgentCallbacks, attachments?: Attachment[], signal?: AbortSignal): Promise<void>

interface Context {
  frontmostApp?: string
  openWindows?: WindowInfo[]
  editorOpenFiles?: string[]
  recentActions?: string[]
  projectPath?: string
}

interface Attachment {
  type: "image"
  path: string
}

interface AgentCallbacks {
  onTextChunk(text: string): void
  onToolCallStart(id: string, tool: string, args: object): void
  onToolResult(id: string, ok: boolean, data?: object, error?: string, detail?: string): void
  onApprovalRequired(summary: string, resolve: (approved: boolean) => void): void
  onSessionCreated(sessionId: string, title: string): void
  onDone(ok: boolean, summary: string): void
}

interface ToolExecutor {
  execute(tool: string, args: object, signal?: AbortSignal): Promise<ToolExecutionResult>
}
```

- ai-module is constructed with two `ToolExecutor` instances (`petAppProxy`: socket proxy
  to pet-app, `editorLocal`: in-process workspace executor). CLI testing substitutes a mock
  executor.
- API key and model name are also injected at construction — the module itself never
  persists them.
- `onToolCallStart`/`onToolResult`'s `id` is that call's `tool_use` id. Claude can emit
  multiple `tool_use` blocks in one turn (parallel tool use), so without `id` the UI
  timeline has no way to attach a result to the call it belongs to.
- `signal` (`AbortSignal`): the user-initiated abort path. On abort, ai-module stops
  streaming, sends `tool_cancel` via `petAppProxy` for any in-flight pet-app executor call,
  then finishes via `onDone(false, "aborted")`.
- `sessionId` (2026-07-29): the caller invokes `run()` once per session and ai-module keeps
  each session's conversation history under this key — a session's memory never bleeds into
  another's (plan/04_ai-module.md 3.4). `Context.projectPath` is auto-filled from the
  session's workspace, so the model doesn't need to repeat it on every `code_editor` call.
- `attachments` (2026-07-29, optional): images attached to this turn (e.g. pet-app's drag
  capture, F14).
- `onSessionCreated` (2026-07-29): fires when the agent calls the `open_task_session` tool on
  its own judgement (see [`tools.md`](./tools.md)). The caller converts this into a
  `session_create(origin=agent)` socket event ([`socket.md`](./socket.md) channel 4) so
  pet-app's sidebar picks up the new session. All subsequent turns of this conversation are
  recorded under the new `sessionId`.

## `ToolExecutionResult` vs the wire `ToolResult`

`ToolExecutor.execute()` resolves with `agent-interface.ts`'s `ToolExecutionResult` — this
is **not** the same type as `events.ts`'s `ToolResult`, which additionally carries the wire
fields `type` and `id`. `ToolExecutionResult` is the pre-wire value; `petAppProxy`'s
implementation is what additionally speaks the wire `ToolResult` format underneath.

## Error codes: `ToolResultErrorCode` vs `ToolErrorCode`

`agent-interface.ts` exports `ToolResultErrorCode`, a superset of `events.ts`'s
`ToolErrorCode` with `denied_by_user` added. `denied_by_user` never crosses the socket —
approval happens inside ai-module before dispatch — so it only ever shows up in what
`onToolResult` reports back to the model, never in a `ToolResult` read off the wire.
