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
{"type":"event","event":"agent_thinking"}
{"type":"event","event":"tool_call","tool":"code_editor","detail":{"path":"src/main.ts"}}
{"type":"event","event":"tool_result","ok":true}
{"type":"event","event":"await_approval","summary":"requesting to run rm -rf ./dist"}
{"type":"event","event":"agent_done","ok":true,"summary":"3 tests passed"}
```

### 3. User input (pet-app -> workspace)

```json
{"type":"user_input","text":"run this project's tests","source":"voice"}
{"type":"user_input","text":"open README","source":"text"}
```

- `source`: `voice` | `text`
