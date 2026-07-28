# ai-module interface

Source of truth: [`../src/types/agent-interface.ts`](../src/types/agent-interface.ts).
This document explains it; the types are normative.

```typescript
run(command: string, context: Context, callbacks: AgentCallbacks, signal?: AbortSignal): Promise<void>

interface Context {
  frontmostApp?: string
  openWindows?: WindowInfo[]
  editorOpenFiles?: string[]
  recentActions?: string[]
}

interface AgentCallbacks {
  onTextChunk(text: string): void
  onToolCallStart(id: string, tool: string, args: object): void
  onToolResult(id: string, ok: boolean, data?: object, error?: string, detail?: string): void
  onApprovalRequired(summary: string, resolve: (approved: boolean) => void): void
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
