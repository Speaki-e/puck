# Avatar `manifest.json` schema

Source of truth: [`../src/types/avatar-manifest.ts`](../src/types/avatar-manifest.ts).
This document explains it; the types are normative. See also
[pet-app/docs/avatar-spec.md](https://github.com/Speaki-e/pet-app/blob/main/docs/avatar-spec.md)
for the full external-avatar-creator guide.

**2026-07-29: primary avatar type switched from 3D usdz to 2D sprites (PNG).** `bounce_intensity`
and `emotions` are new, additive, optional fields — non-breaking, MINOR version.

```json
{
  "schema_version": 1,
  "name": "poko",
  "type": "sprites",
  "scale": 1.0,
  "bounce_intensity": 0.6,
  "hitbox": { "width": 120, "height": 140 },
  "clips": {
    "idle": "idle", "walk": "walk", "climb": "climb",
    "fall": "fall", "land": "land", "point": "point",
    "type": "type", "listen": "listen",
    "react_click": "react_click", "react_drag": "react_drag",
    "kick": "kick"
  },
  "emotions": {
    "happy": "happy", "thinking": "thinking", "sad": "sad"
  },
  "sounds": {
    "walk": "sounds/footstep.wav",
    "point": "sounds/point.wav",
    "react_click": "sounds/boop.wav",
    "kick": "sounds/kick.wav",
    "app_launch": "sounds/launch.wav",
    "task_success": "sounds/ding.wav",
    "task_fail": "sounds/buzz.wav",
    "await_approval": "sounds/awaiting.wav",
    "listen_start": "sounds/listen.wav"
  }
}
```

- `type`: `usdz` | `video` | `sprites` (`sprites` is the primary implementation as of
  2026-07-29; `usdz`/`video` are interface-only, no active development).
- `clips` values are **file stems**: `"walk": "walk"` points at `walk.png` in the same
  directory for `type: sprites` (same stem convention `usdz` used, just a different
  extension). One file per clip — for the old `usdz` type this mattered because RealityKit
  only ever plays a usdz's first animation; for `sprites` it's simply one static image per clip.
- **Required clips: `idle` only** (relaxed from `{idle, walk}` — a single base illustration
  is enough to run). Any other missing clip, including `walk`, falls back to `idle`.
- `kick`: optional clip for the ball-toy interaction (02_pet-app.md F12). Falls back to
  `react_click` or `idle` if absent.
- `emotions` (optional): same stem-dictionary shape as `clips`, keyed by emotion name. When a
  socket event maps to an emotion key present here, pet-app swaps to that image; otherwise it
  keeps whatever clip is currently showing. An avatar with only a base image needs no
  `emotions` table at all.
- `bounce_intensity` (optional, `sprites`-only): 0.0–1.0 multiplier for pet-app's code-driven
  procedural squash-and-stretch motion (idle breathing, walk bounce, land squash-recover, kick
  anticipation-stretch — 02_pet-app.md F2). There are no animation frames to ship for a static
  illustration, so this tunes an effect pet-app applies on top of the image instead. Absent
  means pet-app's own default; `0` means fully static. No effect on `usdz`/`video` avatars.
- For `type: video`, clip values are instead a `{"in":seconds,"out":seconds}` timecode range.
- `sounds` keys mix clip names and event names (`app_launch`, `task_success`, `task_fail`,
  `await_approval`, `listen_start`) — pet-app looks up the same table for both FSM state
  entry and socket events. The event-name keys pair with the reactions in [socket.md](./socket.md)'s
  state events (02_pet-app.md F3 mapping table) — `await_approval`'s "waiting" SFX is this key.
- Scale convention: character height of 1 unit == 100 screen px. `scale` is the multiplier
  applied to the root entity/layer so that the source asset's raw height * `scale` ~= 1 unit
  (i.e. `scale = 1 / raw height`). Normalizing at the source to 1 unit (`scale = 1.0`) is the
  preferred approach; `scale` is a correction fallback, not the primary mechanism.
