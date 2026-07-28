# dummy avatar (development only)

A development-only dummy avatar so the M-A milestone ("the pet roams the
screen/windows without a socket connection") runs immediately after cloning.
`manifest.json` follows the `protocol` repo's section 6 schema as-is.

**2026-07-29: switched from 3D usdz to 2D sprites (PNG).** `idle.png` is now
byeolki's real illustrated character art (from `Speaki-e/assets/speaki.png`),
not a placeholder. Only `idle` is in the manifest right now — every other
clip (`walk`, `climb`, `fall`, `land`, `point`, `type`, `listen`,
`react_click`, `react_drag`, `kick`) falls back to it until matching art for
those poses exists.

## What's here vs. what's still needed

`manifest.json`'s clip values (`"idle": "idle"`) are file stems: each points
at its own PNG living right here next to manifest.json.

- `idle.png` — required, present, real art.
- `walk.png`, `climb.png`, `fall.png`, `land.png`, `point.png`, `type.png`,
  `listen.png`, `react_click.png`, `react_drag.png`, `kick.png` — recommended,
  not yet present (all fall back to idle at runtime with a startup warning).
  `kick` is for the optional F12 ball-toy interaction. Add each to
  `manifest.json`'s `clips` table once its art exists.
- `sounds/*.wav` — the files referenced by `manifest.json`'s `sounds` table
  (not yet included either -- SFXPlayer treats a missing file as silence).

Full requirements for additional clip art (format, resolution, SD
proportions, anchor-point consistency, size budget) are in
[`../../../../docs/avatar-spec.md`](../../../../docs/avatar-spec.md).

Audio binaries are tracked with Git LFS (see `.gitattributes`); `idle.png`
(~760KB) is small enough that LFS isn't necessary for it.
