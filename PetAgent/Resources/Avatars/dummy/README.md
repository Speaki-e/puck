# dummy avatar (development only)

A development-only dummy avatar so the M-A milestone ("the pet roams the
screen/windows without a socket connection") runs immediately after cloning.
`manifest.json` follows the `protocol` repo's section 6 schema as-is.

## Real assets not yet included (owner: 강상우 Sangwoo Kang, to be added)

- `dummy.usdz` — a renamed Meshy preset or similar is enough (see 02_pet-app.md's
  "아바타 리소스 소비" (Avatar Resource Consumption) section). Required clips: `idle`, `walk`. Recommended:
  `climb`, `fall`, `land`, `point`, `type`, `listen`, `react_click`, `react_drag`.
- `sounds/*.wav` — the 7 files referenced by `manifest.json`'s `sounds` table.

usdz/audio binaries are tracked with Git LFS (see `.gitattributes`). Until real
files are added here, `AvatarLoader` is designed to fall back missing clips to
idle and log a startup warning (02_pet-app.md F2).
