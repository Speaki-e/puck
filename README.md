# Puck

A macOS desktop pet that is also an AI agent. Two Swift apps:

- **Puck** — the pet: an always-on-top character that walks your screen, points
  at things, listens for voice, and drives the Mac (`run_shell`,
  `run_applescript`, click/find UI elements, launch apps).
- **PuckClient** — its window: chat, workspaces, git status, a native SwiftUI
  code editor, and a terminal pane.

The two talk over a local socket bridge. The agent core (chat, tools,
approvals, sessions) lives in `pet-app/Puck/Agent`.

## Install

Download `Puck-<version>.dmg` from
[Releases](https://github.com/Speaki-e/puck/releases) and drag **both** apps
into Applications. Not one: the pet and its window are one product talking to
each other over a local socket, and either one alone does nothing. macOS 14 or
newer; both apps are universal (Apple silicon and Intel).

### The first launch is refused, and how to get past it

The apps are signed ad-hoc, not notarised — there is no paid Apple Developer
Program behind this, so macOS has no developer to name and treats the download
as untrusted. Nothing is wrong with the app; this is the same wall every
unnotarised download hits. Two ways through, either is fine:

- **System Settings → Privacy & Security**, scroll to the bottom, and press
  **Open Anyway** next to the blocked app. Do it once for each of the two.
  (On macOS 15 and later this is the only way — Control-clicking the app no
  longer offers it.)
- **Or one line in Terminal**, which drops the quarantine flag from both at
  once:

  ```sh
  xattr -dr com.apple.quarantine /Applications/Puck.app /Applications/PuckClient.app
  ```

### Permissions it will ask for

- **Accessibility** — required, and the pet is inert without it: this is what
  reads the window list it walks on, moves the cursor, and receives the global
  hotkey. Grant it to **Puck.app**.
- **Microphone** and **Speech Recognition** — push-to-talk only. Decline them
  and everything except the microphone button still works.
- **Automation** — asked the first time the agent runs an AppleScript, and
  named per app it wants to drive.

### What it expects to find on your Mac

- **`node`**, for the vendored ACP agent behind the `code_editor` tool and the
  CLI chat provider. Not bundled.
- **A `claude` or `codex` CLI you have already logged into**, for the same two.
  Also not bundled — they are ~256MB per-platform binaries belonging to your
  own account, and the app reuses that login rather than asking for it again.
- **Or an API key**, if you would rather talk to Anthropic/OpenAI directly:
  put it in `~/Library/Application Support/Puck/.env` as
  `ANTHROPIC_API_KEY=…` / `OPENAI_API_KEY=…` (or `CLAUDE_CODE_OAUTH_TOKEN`,
  `CODEX_API_KEY`), and pick the provider in Settings.

## Build

```sh
sh pet-app/scripts/install.sh   # builds + signs both apps into /Applications
```

Needs Xcode, `xcodegen`, and an Apple Development certificate (a free personal
team is fine — a stable signature is what keeps the Accessibility grant alive
across rebuilds).

### Packaging a release

```sh
sh pet-app/scripts/make-dmg.sh   # -> pet-app/build/Puck-<version>.dmg
```

Builds both apps in Release, signs them ad-hoc, refuses to package one
carrying the debug entitlement, and writes one image holding the pair. The
version comes from `MARKETING_VERSION` in `pet-app/project.yml`, which both
apps report — they are only ever installed together, so a version that could
differ between them would describe a pair that cannot exist.

With a real certificate to hand, `SIGN_IDENTITY="Developer ID Application:
NAME (TEAMID)"` signs with it instead; notarising and stapling that image
(`xcrun notarytool submit --wait`, `xcrun stapler staple`) is what removes the
first-launch wall above.

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
creates the folders if they are not there yet.

### The tank

Drop a `seabed.png` into `Tank/` and it replaces the one the app ships. It is
read once at launch, so restart the pet after changing it. It is
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

#### Adding one, start to finish

1. **Open the folder.** Settings → 아바타 → **커스터마이징 폴더 열기**. It creates
   `Avatars/` and `Tank/` if they are not there yet, so this also tells you the
   folder exists.
2. **Make a folder for your character** inside `Avatars/`. Its name is the name
   the picker shows: `Avatars/my-pet/` appears as `my-pet`.
3. **Drop in one PNG and a `manifest.json`.** One drawing is a working
   character — `idle` is the only clip that has to exist and every other state
   falls back to it, so you can start with a single picture and add walking,
   climbing and the rest whenever you feel like it. Transparent background,
   drawn facing right (the pet is mirrored when it walks the other way).
   The smallest manifest that works:

   ```json
   {
     "schema_version": 1,
     "name": "my-pet",
     "type": "sprites",
     "hitbox": { "width": 130, "height": 133 },
     "clips": { "idle": "idle" }
   }
   ```

   `hitbox` is the size it will be drawn and clicked at, in points — match your
   drawing's proportions or it will look squashed.
4. **Load it.** Settings → 아바타 → **아바타 다시 불러오기**, then press **선택**
   next to its name. No restart: the reload button rebuilds the running pet
   from what is on disk, which is also how you see a redrawn sprite or an
   edited manifest without quitting.

If something is wrong with the package the pet does not change and the reason
is in the log (`~/Library/Application Support/Puck/logs/`) — a missing `idle`
file, a manifest that will not parse, or a `schema_version` this build does not
know. The import button (**아바타 패키지 가져오기…**) takes a folder like the
above and copies it in for you, and it checks the package before it does,
so it is the louder way to find out what is missing.

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
- Only `schema_version`, `name`, `type`, `hitbox` and `clips` have to be there.
  `scale` defaults to 1, `sounds` and `emotions` to nothing at all, and
  `bounce_intensity` to the app's own default.
- Paths in the manifest stay inside the package: a name that climbs out of it
  is refused rather than read.

`pet-app/Puck/Resources/Avatars/dummy` is a complete example, and Settings'
import button takes a folder like the above and copies it in for you.

## Docs

- [`docs/decisions.md`](docs/decisions.md) — why the cross-cutting changes happened
- [`docs/verification.md`](docs/verification.md) — release criteria + manual desktop checks
- [`pet-app/design.md`](pet-app/design.md) — app design notes
