# Avatar `manifest.json` schema

Source of truth: [`../src/types/avatar-manifest.ts`](../src/types/avatar-manifest.ts).
This document explains it; the types are normative. See also
[pet-app/docs/avatar-spec.md](https://github.com/Speaki-e/pet-app/blob/main/docs/avatar-spec.md)
for the full external-avatar-creator guide.

```json
{
  "schema_version": 1,
  "name": "poko",
  "type": "usdz",
  "scale": 1.0,
  "hitbox": { "width": 120, "height": 140 },
  "clips": {
    "idle": "idle", "walk": "walk", "climb": "climb",
    "fall": "fall", "land": "land", "point": "point",
    "type": "type", "listen": "listen",
    "react_click": "react_click", "react_drag": "react_drag"
  },
  "sounds": {
    "walk": "sounds/footstep.wav",
    "point": "sounds/point.wav",
    "react_click": "sounds/boop.wav",
    "app_launch": "sounds/launch.wav",
    "task_success": "sounds/ding.wav",
    "task_fail": "sounds/buzz.wav",
    "await_approval": "sounds/awaiting.wav",
    "listen_start": "sounds/listen.wav"
  }
}
```

- `type`: `usdz` | `video` | `sprites` (first implementation is `usdz` only).
- `clips` values are **file stems**: `"walk": "walk"` points at `walk.usdz` in the same
  directory. One usdz file per clip, one animation per file — RealityKit effectively only
  ever plays a usdz's first animation, so baking multiple named clips into a single usdz
  and selecting by animation name does not work (see 02_pet-app.md F2).
- Required clips: `idle`, `walk`. Any other missing clip falls back to `idle`.
- For `type: video`, clip values are instead a `{"in":seconds,"out":seconds}` timecode range.
- `sounds` keys mix clip names and event names (`app_launch`, `task_success`, `task_fail`,
  `await_approval`, `listen_start`) — pet-app looks up the same table for both FSM state
  entry and socket events. The event-name keys pair with the reactions in [socket.md](./socket.md)'s
  state events (02_pet-app.md F3 mapping table) — `await_approval`'s "waiting" SFX is this key.
- Scale convention: character height of 1 unit == 100 screen px. `scale` is the multiplier
  applied to the root entity so that the source mesh's raw height * `scale` ~= 1 unit (i.e.
  `scale = 1 / raw height` — e.g. a rig with raw height 180 units needs `scale ~= 0.00556`).
  Normalizing at the source to 1 unit (`scale = 1.0`) is the preferred approach; `scale` is a
  correction fallback, not the primary mechanism.
