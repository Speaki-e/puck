# Avatar package spec (for external creators)

Avatar/sound assets are produced outside the pet-app team. This document is
what to hand a creator (or follow yourself when building the dev dummy
avatar) so the package works with `AvatarLoader`/`AvatarImportValidator`
without back-and-forth. The manifest schema itself is normative in the
`protocol` repo (section 6); this doc adds the parts specific to how pet-app
actually loads usdz clips.

## Why one usdz per clip, not one usdz for the whole avatar

The original plan assumed a single usdz containing every animation (idle,
walk, climb, ...), picked by name at runtime via `availableAnimations`. That
doesn't work: RealityKit effectively only plays a usdz's **first** animation
regardless of how many `availableAnimations` entries it reports, and Reality
Converter itself only reads a source file's first animation when producing a
usdz. Packing 10 named clips into one file and selecting by name is not
something the current toolchain supports.

Instead: **each clip is its own usdz file, containing exactly one
animation**, sitting next to `manifest.json` in the same avatar directory.
`manifest.json`'s `clips` values are file stems, not animation names:

```
Avatars/{name}/
├── manifest.json
├── idle.usdz
├── walk.usdz
├── climb.usdz
├── fall.usdz
├── land.usdz
├── point.usdz
├── type.usdz
├── listen.usdz
├── react_click.usdz
├── react_drag.usdz
└── sounds/
    ├── footstep.wav
    ├── point.wav
    ├── boop.wav
    ├── launch.wav
    ├── ding.wav
    ├── buzz.wav
    └── listen.wav
```

A manifest clip entry `"walk": "walk"` means: load `walk.usdz` from this same
directory, take its (only) animation, and play it. If `manifest.json`'s
`type` is ever `sprites`, the same file-stem convention applies to whatever
sprite-sheet naming AvatarLoader ends up using; `video` type instead uses a
`{"in":sec,"out":sec}` time range into a single video file (unaffected by
this usdz-specific issue).

## Clip list

| Clip | Required? | Notes |
|---|---|---|
| `idle` | **Required** | No fallback target if missing — load is rejected outright. |
| `walk` | **Required** | Same. |
| `climb` | Recommended | Falls back to idle if missing (with a startup warning). |
| `fall` | Recommended | " |
| `land` | Recommended | " |
| `point` | Recommended | " |
| `type` | Recommended | " |
| `listen` | Recommended | No direct source in most free animation libraries (see below) — a subtle idle variant or head-nod-style clip is an acceptable substitute. |
| `react_click` | Recommended | " |
| `react_drag` | Recommended | No direct source either — a "hanging/dangling" clip reads well for "being dragged by the cursor." |

## Per-file requirements

- **Single root bone, Y-up.**
- **Height = 1 unit**, rendered at 100px in-app (`manifest.json`'s top-level
  `scale` field compensates if a source asset isn't natively 1 unit tall —
  but normalizing the mesh itself in Blender before export is more reliable
  than relying on `scale` to fix a large mismatch).
- **Loop clips** (`idle`, `walk`, `climb`, `type`, `listen`) need their first
  and last frame to match pose — otherwise the loop visibly pops. Mixamo's
  "In Place" + looping export options handle most of this, but verify the
  result in Blender before shipping.
- **One animation per file** (see above) — trim everything else out before
  exporting to usdz.
- **Size budget:** ~2MB per clip file as a guideline (~20MB total across all
  clips for one avatar, matching the original single-file budget spread
  across ~10 files). Low-poly meshes (a few thousand triangles) stay well
  under this.

## Suggested sources

- **Mesh:** [Quaternius Universal Base Characters](https://quaternius.com/)
  or [Kenney Character Assets](https://kenney.nl/) — both CC0, no attribution
  required, no licensing friction. Kenney's more overtly low-poly style
  actually reads better at 100px than a higher-detail mesh.
- **Animation:** [Mixamo](https://www.mixamo.com/) (free, Adobe account) —
  upload a CC0 mesh, it auto-rigs and lets you download individual
  animations. Mixamo's terms allow embedding the animation data in an app;
  redistributing the raw animation files themselves is not allowed. Since
  this project isn't distributed on the App Store, that's a low-risk fit.
  Avoiding Adobe entirely is possible via Quaternius's own Universal
  Animation Library, but coverage for the more unusual clips (`climb`,
  `type`, `listen`) is thinner there.

Candidate Mixamo animation names per clip (verify against the actual library
— names below are best-effort research, not confirmed against a live
Mixamo session):

| Clip | Candidate | Confidence |
|---|---|---|
| `idle` | Idle / Breathing Idle | High |
| `walk` | Walking | High |
| `fall` | Falling Idle | High |
| `type` | Typing | High |
| `point` | Pointing | High |
| `climb` | Climbing / Climbing Ladder | Medium |
| `land` | Falling To Landing / Hard Landing | Medium |
| `react_click` | Hit Reaction (some variant) | Medium |
| `listen` | No direct match — substitute | Low |
| `react_drag` | No direct match — Hanging Idle reads as "dangling from the cursor" | Low |

## Pipeline

Mixamo only exports FBX; Reality Converter doesn't accept FBX (only
obj/gltf/usd). **Blender is a required intermediate step**: import the FBX,
trim to one animation, normalize scale/orientation, export as USD, then
convert to usdz (Reality Converter or `usdzconvert`).

Common pitfall: Mixamo/Quaternius humanoid rigs typically export at roughly
1.8 units tall (meters). Left as-is, that renders at ~180px instead of the
intended 100px. Normalize height to 1 unit in Blender before export rather
than trying to compensate purely via `manifest.json`'s `scale` field.

## What the import validator checks (and what it doesn't, yet)

`AvatarImportValidator` checks: manifest schema/version, required clips
present in the manifest, and — per this doc's file-per-clip design — that
each required/recommended clip's `{name}.usdz` file actually exists on disk
and is under the size budget. It reports missing/oversized files so a bad
package is rejected with a clear reason instead of loading partially broken.

It does **not** yet check actual mesh height/scale or loop pose-matching —
that needs loading the usdz through RealityKit/ModelIO and inspecting it,
which depends on Task 8 (Overlay rendering) landing and a real usdz fixture
to verify the check against. Until then, height/loop correctness is a manual
verification step when a package is first tried against the running app.
