# dummy avatar (development only)

A development-only dummy avatar so the M-A milestone ("the pet roams the
screen/windows without a socket connection") runs immediately after cloning.
`manifest.json` follows the `protocol` repo's section 6 schema as-is.

## Real assets not yet included (owner: 강상우 Sangwoo Kang, to be added)

**One usdz per clip, not one usdz for the whole avatar.** RealityKit
effectively only plays a usdz's first animation no matter how many
`availableAnimations` entries it reports, so `manifest.json`'s clip values
(`"idle": "idle"`, `"walk": "walk"`, ...) are file stems: each needs its own
single-animation file living right here next to manifest.json.

- `idle.usdz`, `walk.usdz` — required.
- `climb.usdz`, `fall.usdz`, `land.usdz`, `point.usdz`, `type.usdz`,
  `listen.usdz`, `react_click.usdz`, `react_drag.usdz` — recommended (missing
  ones fall back to idle at runtime with a startup warning).
- `sounds/*.wav` — the 7 files referenced by `manifest.json`'s `sounds` table.

Full requirements for whoever produces these (mesh/rig rules, scale, loop
pose-matching, size budget, candidate clip sources) are in
[`../../../../docs/avatar-spec.md`](../../../../docs/avatar-spec.md).

usdz/audio binaries are tracked with Git LFS (see `.gitattributes`).
