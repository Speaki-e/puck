# dummy avatar (development only)

A development-only dummy avatar so the M-A milestone ("the pet roams the
screen/windows without a socket connection") runs immediately after cloning.
`manifest.json` follows the `protocol` repo's section 6 schema as-is.

**2026-07-29: switched from 3D usdz to 2D sprites (PNG).** The art is
byeolki's real illustrated character (from `Speaki-e/assets/`), not a
placeholder.

**2026-07-29: the full expression set is in.** All 12 clips and 16 emotions
now have their own PNG — nothing falls back to idle any more.

## What's here

`manifest.json`'s clip and emotion values are file stems: each points at its
own PNG living right here next to manifest.json.

**Every one of these images is the same seated pose with a different face.**
They are expression variants, not motion frames, which is why they are
assigned by what the pet is *feeling* in each state rather than by limb
position — the motion itself comes from `BouncePreset`'s procedural
squash/stretch and rotation, not from the art. Assigning them any other way
(e.g. picking one as a "walk cycle") would not read as movement.

**File names describe the expression, not the slot it fills.** The manifest
key is the fixed contract (the FSM plays `"climb"`, `EventRouter` emits
`"sad"`); the stem beside it says what is actually drawn, so picking art for
a new slot is a matter of reading the names rather than opening 28 files.
Re-pointing a slot is a one-word edit in `manifest.json` and needs no file
renaming at all.

**Clips** — `clips` in the manifest, keyed by FSM state clip key. `kick` and
`pet` belong to the optional F12 ball-toy and double-tap petting interactions.

| Clip key | File | Expression |
|---|---|---|
| `idle` | `starry-eyed.png` | wide sparkling eyes, delighted |
| `walk` | `humming.png` | small contented smile |
| `climb` | `determined.png` | eyes screwed shut with effort |
| `fall` | `yikes.png` | eyes blown wide, caught out |
| `land` | `dazed.png` | blank stare, mouth open |
| `point` | `eureka.png` | bright-eyed, calling out |
| `type` | `in-the-zone.png` | half-lidded, pleased with itself |
| `listen` | `all-ears.png` | shining eyes, hanging on every word |
| `react_click` | `startled.png` | frozen, pale |
| `react_drag` | `flustered.png` | confused wobble |
| `kick` | `giddy.png` | helpless laughter |
| `pet` | `melting.png` | blissed out, head tilted |

**Emotions** — `emotions`, swapped in by `EventRouter` and the Settings
mapping. `happy`, `thinking` and `sad` are the three `EventRouter` drives by
name; they must always exist. The rest are free for the Settings mapping.

| Emotion key | File | Expression |
|---|---|---|
| `happy` | `beaming.png` | eyes closed, big grin |
| `thinking` | `pondering.png` | heavy-lidded, weighing it up |
| `sad` | `welling-up.png` | quiet tears |
| `angry` | `grumpy.png` | scrunched up, unimpressed |
| `love` | `smitten.png` | sparkling, adoring |
| `wink` | `cheeky.png` | one eye shut, blushing |
| `laugh` | `giggly.png` | eyes creased, laughing |
| `cry` | `sobbing.png` | full waterworks |
| `worried` | `fretting.png` | small anxious mouth |
| `excited` | `thrilled.png` | eyes wide with delight |
| `surprised` | `agape.png` | caught mid-gasp |
| `relieved` | `phew.png` | eyes shut, breathing out |
| `content` | `serene.png` | calm, settled |
| `cheerful` | `sunny.png` | warm open smile |
| `shy` | `bashful.png` | hidden under the hat |
| `shadow` | `spooked.png` | blacked-out silhouette |
- `sounds/*.wav` — the files referenced by `manifest.json`'s `sounds` table
  (not yet included -- SFXPlayer treats a missing file as silence).

`DummyAvatarPackageTests` guards all of this: it runs the import validator
over this directory, checks every referenced stem has a PNG, and fails if the
FSM plays a clip key the manifest doesn't define. Those failures are all
silent at runtime, so the test is the only thing that catches them.

## Adding or replacing art

Every canvas here is 1200x1224 with the character in the same place (alpha
bounding boxes agree within 2px). Keep it that way: `visualBounds` measures
the artwork's real outline from its alpha, so a clip framed differently makes
the pet jump the moment that clip starts playing.

Full requirements for additional clip art (format, resolution, SD
proportions, anchor-point consistency, size budget) are in
[`../../../../docs/avatar-spec.md`](../../../../docs/avatar-spec.md).

Audio binaries are tracked with Git LFS (see `.gitattributes`); `idle.png`
(~760KB) is small enough that LFS isn't necessary for it.
