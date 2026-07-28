# Log format (distributed debugging standard)

Source of truth: [`../src/types/logging.ts`](../src/types/logging.ts).
This document explains it; the types are normative.

Every part of the tool-call path (the agent core, both executors) writes JSON Lines logs
in this format:

```json
{"ts":"2026-07-26T12:00:00.000Z","src":"agent","kind":"tool_call","id":"t1","tool":"launch_app","args":{"app_name":"Safari"}}
{"ts":"...","src":"pet-app","kind":"tool_exec_start","id":"t1"}
{"ts":"...","src":"pet-app","kind":"tool_exec_end","id":"t1","ok":true}
{"ts":"...","src":"agent","kind":"tool_result","id":"t1","ok":true}
```

- `src`: `agent` | `pet-app` | `workspace`
- File location: `~/Library/Application Support/PetAgent/logs/` (rotated daily)
- Joining the three sources' logs on the same `id` reconstructs a call's full path.
- The four `kind` values above are what's implemented today. This isn't meant to be a
  closed set — new `kind` values may be added as logging coverage grows. Treat an
  unrecognized `kind` as forward-compatible, not a parse error.
