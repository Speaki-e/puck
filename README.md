# Puck

A macOS desktop pet that is also an AI agent. Two Swift apps:

- **Puck** — the pet: an always-on-top character that walks your screen, points
  at things, listens for voice, and drives the Mac (`run_shell`,
  `run_applescript`, click/find UI elements, launch apps).
- **PuckClient** — its window: chat, workspaces, git status, a native SwiftUI
  code editor, and a terminal pane.

The two talk over a local socket bridge. The agent core (chat, tools,
approvals, sessions) lives in `pet-app/Puck/Agent`.

## Build

```sh
sh pet-app/scripts/install.sh   # builds + signs both apps into /Applications
```

Needs Xcode, `xcodegen`, and an Apple Development certificate (a free personal
team is fine — a stable signature is what keeps the Accessibility grant alive
across rebuilds).

## Test

```sh
sh pet-app/scripts/test.sh   # PuckTests + a PuckClient build
```

Unattended, exits nonzero on any failure. Tests needing something this machine
may lack (`node`, a `claude`/`codex` CLI) skip rather than fail.

## Agent providers

Normal chat talks to the Anthropic or OpenAI API directly. The `code_editor`
tool instead runs a vendored ACP agent under `node`, which needs its vendor's
CLI (`claude` or `codex`) installed. Credentials go in Puck's `.env`:
`ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`, or `CODEX_API_KEY` /
`OPENAI_API_KEY`.

## Making it your own

Everything you can swap lives in one folder:

```
~/Library/Application Support/Puck/
    Avatars/<name>/     one folder per character
    Tank/seabed.png     the picture the island is filled with
```

Settings has a button that opens it (아바타 → 커스터마이징 폴더 열기), which also
creates the folders if they are not there yet. Both are read at launch, so
restart the pet after dropping something in.

### The tank

Drop a `seabed.png` into `Tank/` and it replaces the one the app ships. It is
scaled to the island's height with the sides cropped, and repeated end to end
if the window is wider than one copy — so a wide, shallow picture (the bundled
one is 3596×447) fits without repeating on most windows.

### A character

An avatar is a folder with a `manifest.json` and one PNG per clip beside it:

```
Avatars/my-pet/
    manifest.json
    idle.png  walk.png  fall.png  …
    sounds/*.wav
```

`manifest.json`, with the fields that matter:

```json
{
  "schema_version": 1,
  "name": "my-pet",
  "type": "sprites",
  "scale": 1.0,
  "bounce_intensity": 0.6,
  "hitbox": { "width": 130, "height": 133 },
  "clips":    { "idle": "idle", "walk": "walk" },
  "emotions": { "happy": "beaming" },
  "sounds":   { "land": "sounds/waah.wav" }
}
```

- **`clips`** maps a state to a file *stem*: `"idle": "starry-eyed"` draws
  `starry-eyed.png`. `idle` is the only one required — everything else falls
  back to it, so a single drawing is a working character. The rest are `walk`,
  `climb`, `fall`, `land`, `point`, `type`, `listen`, `react_click`,
  `react_drag`, `kick`, `pet` and `spin`.
- **`emotions`** are swapped in when the agent reacts (`happy`, `thinking`,
  `sad`, `angry`, `love`, `wink`, `laugh`, `cry`, …), same file-stem rule.
- **`sounds`** are paths inside the package, and may sit in a subfolder. Keys
  are clip names plus a few events: `app_launch`, `task_success`, `task_fail`,
  `listen_start`, `kick_<toy>`, `chatter_*`.
- **`hitbox`** is the character's size in points at `scale` 1 — what the pet is
  clicked, stood and thrown by. **`bounce_intensity`** (0–1) is how much the
  squash-and-stretch shows on a still drawing.
- Paths in the manifest stay inside the package: a name that climbs out of it
  is refused rather than read.

`pet-app/Puck/Resources/Avatars/dummy` is a complete example, and Settings'
import button takes a folder like the above and copies it in for you.

## Docs

- [`docs/decisions.md`](docs/decisions.md) — why the cross-cutting changes happened
- [`docs/verification.md`](docs/verification.md) — release criteria + manual desktop checks
- [`pet-app/design.md`](pet-app/design.md) — app design notes
