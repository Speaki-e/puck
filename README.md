# protocol

Shared contract between `pet-app`, `workspace`, and `ai-module`. Nobody owns this repo
specifically — changes go through PRs approved by the teams they affect (see
[Change management](#change-management)).

Consuming repos should reference this contract only through what's defined here, never
by reading each other's source.

## Contents

| Path | Content |
|---|---|
| [`docs/socket.md`](docs/socket.md) | Socket channels and message formats |
| [`docs/tools.md`](docs/tools.md) | Tool registry |
| [`docs/agent-interface.md`](docs/agent-interface.md) | ai-module's interface |
| [`docs/avatar-manifest.md`](docs/avatar-manifest.md) | `manifest.json` schema |
| [`docs/logging.md`](docs/logging.md) | Tool call/result log format |
| [`src/types/events.ts`](src/types/events.ts) | `BridgeMessage` union (socket wire types) |
| [`src/types/tools.ts`](src/types/tools.ts) | Tool registry data + types (real `.ts`, not `.d.ts` — the registry's executor/timeout/approval fields are runtime values a declaration file can't hold) |
| [`src/types/agent-interface.ts`](src/types/agent-interface.ts) | `Context`/`AgentCallbacks`/`ToolExecutor` types |
| [`src/types/avatar-manifest.ts`](src/types/avatar-manifest.ts) | `AvatarManifest` schema types |
| [`src/types/logging.ts`](src/types/logging.ts) | Log entry types |
| [`src/validate.ts`](src/validate.ts) | Runtime `isBridgeMessage` guard for JSON parsed off the socket |
| [`swift/BridgeMessages.swift`](swift/BridgeMessages.swift), [`swift/JSONValue.swift`](swift/JSONValue.swift) | Swift `Codable` reference mirror of `events.ts` — pet-app copies these files |

## Using this package

Consumers install a specific tag, not `main`:

```
npm install git+https://github.com/Speaki-e/protocol.git#v0.1.0
```

```ts
import { TOOL_REGISTRY, isBridgeMessage, type BridgeMessage } from "@speaki-e/protocol";
```

`npm install` runs this package's `prepare` script (`tsc`), which compiles `src/*.ts` to
`dist/*.js` + `dist/*.d.ts`. Consumers always resolve the compiled `dist/` output — never
raw `src/` — so the registry's runtime values are correct regardless of the consumer's own
toolchain (plain Node, a bundler, etc).

## Development

```
npm install
npm run build   # tsc -> dist/
npm test        # compiles src+tests to dist-test/ and runs them with node --test
```

## Change management

1. All changes go through a PR — no direct pushes to `main`.
2. Required approvals: one representative from each team the change affects (a socket
   change needs 팀1+팀2 sign-off, a new tool needs 팀3 + whichever team owns its executor,
   a manifest change needs 팀1 + 정가은).
3. Schema changes get a semver tag (major if breaking) — each consuming repo tracks a tag,
   never a commit.
4. A schema PR that doesn't update both the TypeScript types and the Swift reference
   together gets rejected.
