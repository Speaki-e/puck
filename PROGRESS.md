# pet-app progress

Live status tracker for implementation work. Updated as tasks complete —
check here instead of asking for a status recap. Full design rationale is in
[`docs/directory-structure.md`](docs/directory-structure.md); implementation
order (P0-P9) is defined in `plan/02_pet-app.md` section 2.

**Last updated:** 2026-07-29 · **Tests:** 466 passing (`xcodebuild test`) · **`main`:** `f3e4586`

**M-A is closed.** The pet renders from committed assets, wanders on its own, walks up and along windows, falls when they go away, and reacts to being clicked and dragged. All PRs including #9 (`feat/pet-interaction`) are merged into `main`.

**2026-07-28: pulled + merged #9, ran a second self-review pass, fixed what it found.** `git pull` initially failed (`git-lfs` wasn't installed on this machine, which is now required — the real usdz/wav assets are committed via LFS as of #7); installed it, redid the pull, fast-forward-merged `feat/pet-interaction` on top. 6 parallel review agents covered every new/changed subsystem from the just-merged commits; the following were confirmed (independently, by 2+ reviewers in most cases) and fixed, see the "2026-07-28 review pass" entry under Review history for detail: a crash on malformed `find_ui_element` pid JSON, a dropped `tool_result` on overlapping `point_at` calls, `CharacterBody.position` desyncing from the rendered avatar on display-rebuild/summon, `ReactDragState` losing its drag-start position to `enter()`'s reset, `WalkOnTopState` walking pets off the very window edge they'd just climbed, and `ReactClickState` not restarting on rapid re-click. Also manually verified on-device (real committed asset pack, not a placeholder) that the redesigned mesh-sharing `USDZAvatar` genuinely plays distinct, moving animation for `walk` (position change + visibly different leg pose across frames) — `fall`/`land`/`react_click` share the identical code path but weren't each individually screenshotted.

**Every planned feature now exists.** F1-F7, F10, F11 are implemented and wired; all 8 pet-app tools are registered in `ToolExecutor`. What remains is cleanup and the cross-repo `protocol` contract, not missing features.

**All 13 planned implementation tasks are now done.** Every module in `docs/directory-structure.md` exists and is wired together in a real `AppDelegate.applicationDidFinishLaunching` bootstrap: permission self-check -> menu bar -> overlay/avatar/FSM/SFX -> window sensing -> tool executor -> bridge server (with `EventRouter` now wired to the live `characterController`/`sfxPlayer`, closing the gap noted in the previous update) -> global hotkeys -> voice input -> text bubble fallback.

**Manually verified end-to-end on-device, twice:** built the real signed `.app`, launched it via `open`, confirmed via `pgrep` it stayed running (including with `BridgeServer`/`WindowListWatcher`/`GlobalHotkeyManager` now live), screenshotted the real screen (`screencapture`), and read the PNG back — a usdz model rendered transparently over other windows both before and after the full bootstrap wiring was added. Also confirmed via the real `AppLogger` JSONL log files that `PermissionOnboarding` and the rest of the chain ran for real across both launches, not just compiled.

**강상우's real animated usdz pack is now in local use** (`death`/`idle`/`jumping`/`punching`/`running`/`walking.usdz`, not committed — same "local Application Support only" pattern as before). Mapped into the dummy manifest as `idle`->`idle`, `walk`->`walking`, `fall`->`death`, `react_click`->`punching`; `jumping`/`running` are currently unreferenced by any FSM clip slot (no obvious fit among the remaining `climb`/`land`/`point`/`type`/`listen`/`react_drag` recommended clips — left in the directory unused rather than force-mapped). Swapping in a real mesh immediately surfaced a real bug: `AvatarManifest.scale` was decoded but never applied anywhere in `USDZAvatar` — harmless with the placeholder Crayon.usdz (already ~1 unit tall) but the real Mixamo-sourced rig measures ~180 units tall raw (`usdcat`/a throwaway `Entity.load` + `visualBounds` check confirmed this — a baked `xformOp:scale=(100,100,100)` from the gltf2usd conversion pipeline stacked on the source rig's own scale), so it rendered ~100x oversized, filling the whole screen. Fixed by applying `manifest.scale` to `rootEntity.scale` in `USDZAvatar.init` and setting the dummy manifest's `scale` to `0.00554` (`1/180.51`) to compensate. Re-verified on-device: the model now renders at the intended ~100px human-figure size at screen center.

## Legend

- [x] done and pushed to `main`
- [~] in progress
- [ ] not started

## Build/infra

- [x] `project.yml` (xcodegen) as the single source of truth for the Xcode project — `.xcodeproj`/`Info.plist` are generated, not committed
- [x] `PetAgent.entitlements` (`com.apple.security.automation.apple-events`, ahead of P7's `run_applescript` need)

## Implementation order (P0-P9) vs. status

| Order | Item | Status |
|---|---|---|
| P0 | F1 overlay + rendering (`Overlay/`) | [x] done, manually verified on-device (see above) |
| P1 | F2 avatar loader + F3 FSM skeleton | [x] done |
| P2 | F3 on-screen movement, multi-display | [~] movement done (`MovementSolver`, `CharacterBody`, `StateContext`, `FrameClock`; all 12 states have behavior). Multi-display still single-window: the avatar lives on `windows.first` only |
| P3 | F4 level 1 + moving on top of windows | [x] done — `WindowSupport` + `StateContext.windows` drive Walk→Climb→WalkOnTop→Fall→Land; `landingY` comes from `LandingSurfaceResolver` |
| P4 | F5 SFX | [x] done |
| P5 | F6 global hotkeys + text input | [x] done |
| P6 | F7 PTT+STT | [x] done |
| P7 | socket server + F11 executor | [x] done — 8/8 handlers registered. `BridgeMessageRouter` hops socket messages to the main thread before touching RealityKit |
| P8 | F4 level 2 + F10 pointing | [x] done — `UIElementSearch`/`UIElementInspector`/`FindUIElementHandler` verified against a live Calculator; `point_at` now walks the pet there and replies at Point start |
| P9 | F10 click_element, avatar-switch UI | [x] `SyntheticClick`/`ClickElementHandler` and `Settings/AvatarManagementView` (import/validate/install flow) done |
| — | Settings/Diagnostics/App bootstrap | [x] done — `PermissionOnboarding`, `MenuBarController`, `SettingsView`, `AppLogger`, full `AppDelegate` wiring of every module above |

Order was reshuffled versus the plan doc's literal P0-P9 sequence to front-load
modules that don't depend on rendering (F1) — see
`docs/directory-structure.md` section 4 for the mapping.

## Detail by module

| Module | Files | Tests | Notes |
|---|---|---|---|
| Bridge (F11/socket) | `BridgeMessages`, `JSONValue`, `BridgeServer`, `BridgeConnection`, `EventRouter` | 44 | Real end-to-end UDS socket test (no mocks). Listener-failure detection, single-instance guard, buffer cap all added post-review. |
| Avatar (F2) | `AvatarManifest`, `AvatarLoader`, `AvatarPlayable`, `AvatarImportValidator`, `USDZAvatar` | 26 | **Design correction**: one usdz per clip, not one shared usdz (RealityKit only plays a usdz's first animation) — see `docs/avatar-spec.md`. Validator checks clip-file existence + size budget; mesh height/scale/loop still manual. `USDZAvatar` now applies `manifest.scale` to `rootEntity` (found missing when a real ~180-unit-tall rig exposed it — see below). Manually verified rendering a real animated usdz on-device at the correct size. `VideoAvatar`/`SpriteAvatar` still stubs (later priority per plan). |
| Movement (F3) | `CharacterController`, `GlobalScreenSpace`, `WanderScheduler`, `StateHandler`, 12 states | 20 | FSM skeleton + coordinate normalization done; per-state movement math (actual walking/climbing/falling) still TODO, needs F1/F4 live data. |
| WindowSensing (F4 level 1) | `WindowInfo`, `WindowListWatcher`, `LandingSurfaceResolver`, `AccessibilityPermission` | 12 | Level 2 (`UIElementInspector`, `ScreenCaptureFallback`) not started. |
| Tools (F11) | `ToolExecutor`, `ToolExecutionLogger`, 7/8 handlers | 13 | `LaunchAppHandler`, `ListRunningAppsHandler`, `GetFrontmostWindowHandler`, `RunShellHandler`, `RunAppleScriptHandler`, `PointAtHandler`, `ClickElementHandler` real. `FindUIElementHandler` still blocked on F4 level 2. |
| Overlay (F1) | `OverlayWindow`, `OverlayWindowController`, `ScreenManager`, `ScreenSpaceMapper`, `ClickThroughController`, `PetARView` | 20 | One window+`PetARView` per real display, positioned via AppKit frames (not the normalized FSM-logic space). Found/fixed a real API bug: macOS's `ARView` has no `cameraMode`/`automaticallyConfigureSession` at all (no camera-passthrough AR on Mac) — plan doc corrected. Alpha-halo mitigation steps 2-4 and idle frame-rate downshift need a real avatar to evaluate against; not implemented speculatively. |
| Audio (F5) | `SFXPlayer`, `PlayerNodePool`, `SoundTable`, `FocusModeObserver` | 12 | `SFXTriggering` protocol gained a `loop` param (symmetric with `AvatarPlayable.play`) so F5 knows which triggers should loop. Fade-out-on-loop-replace stops immediately for now (documented TODO, needs a real sound to tune a volume ramp against). `FocusModeObserver` is explicitly best-effort/unverified on modern macOS — see its doc comment. |
| Input (F6) | `HotkeyBindings`, `GlobalHotkeyManager`, `TextInputBubbleWindow`, `TextInputBubbleView` | 17 | `HotkeyDecisionMaker` handles releasing the modifier before the key during PTT hold (flagsChanged), matching the plan's explicit mention of that event type. `TextInputBubbleWindow` is the one window allowed to become key. |
| Voice (F7) | `VoiceInputController`, `SpeechRecognitionService`, `MicrophonePermission` | 7 | On-device-vs-server STT decided upfront via `supportsOnDeviceRecognition`, not reactive error retry (unstable across macOS versions). Holds under 0.3s still occupy the mic but their final transcription is discarded. `stopStreaming()` no longer cancels early (was losing real final results); a generation counter guards against cross-session result contamination. `onError` now flows protocol -> controller -> AppDelegate instead of being dropped. |
| Pointing (F10) | `PointingController`, `ClickDetector`, `SyntheticClick` | 7 | `beginPointing()` assumes the FSM already arrived at the target -- MoveTo's real movement math isn't implemented yet. System-dialog click classification needs F4 level 2. |
| Settings/Diagnostics/App bootstrap | `AppDelegate`, `MenuBarController`, `PermissionOnboarding`, `AppLogger`, `SettingsView`, `AvatarManagementView` | 8 | `AppDelegate.applicationDidFinishLaunching` wires every module: permission self-check -> menu bar -> overlay/avatar/FSM/SFX -> window sensing -> tool executor (7 handlers) -> bridge server (`EventRouter.reaction(for:)` now applied to the real `characterController`/`sfxPlayer`) -> global hotkeys -> voice input, with a text-bubble fallback when there's no active bridge connection. `AvatarManagementView` wires `NSOpenPanel` -> `AvatarImportValidator` -> install to `Application Support`. |

## Known gaps / blocked items

Ordered by what actually blocks progress.

- **`protocol` repo is empty — this blocks two other teams, not us.**
  workspace's W5 and ai-module's A2 both wait on `types/`. pet-app has
  already implemented the contract in Swift out of necessity
  (`Bridge/BridgeMessages.swift`, `Avatar/AvatarManifest.swift`,
  `Tools/ToolExecutor.swift` error codes), so the TS types should be
  written to match the shipped Swift. **All of `protocol/CLAUDE.md`'s open
  questions are now resolved at the normative source** (`plan/01_protocol.md`,
  commits `8957026`/`2509674`/`d86ee6a`, byeolki's call since nothing
  outside pet-app is implemented yet): `sounds` defines `await_approval`;
  `clips` values are documented as file stems (one usdz per clip); `frame`
  is defined as global Quartz coordinates (top-left origin, Y down,
  points); `unknown_tool` is a standard error code distinct from
  `execution_failed`; `tool_result` has an optional `detail` field for
  human-readable failure specifics; and `scale` semantics are defined as
  raw-height × scale ≈ 1 unit. pet-app implements all of it (`unknown_tool`
  + `detail` landed with tests in the same pass). A full plan-suite
  evaluation then settled two more contract pieces, implemented here as
  the reference (`85f9282`, 314 tests): the `tool_cancel` wire message +
  `cancelled` standard code (abort path for in-flight tools — previously
  nothing could stop a running 600s `code_editor` call), and defined
  disconnect semantics (workspace rejects pending dispatches on drop;
  pet-app finishes in-flight work and drops the unsendable reply with a
  log — matching what it already did). What remains is purely
  transcription: write `types/` + `swift/` in the protocol repo from
  `plan/01_protocol.md` and the shipped Swift.
- **CPU while idle is ~25-33%, and no clean fix exists via ARView's own API.**
  `sample` puts essentially all of it in `ARView.commonRenderCallback()` —
  RealityKit renders on its own `CVDisplayLink`-driven loop regardless of FSM
  tick rate, so `IdleFrameRatePolicy` (F1's 60→15 downshift) changes nothing
  measurable. It also barely engages: F3's wander timer fires every 8-30s, so
  the pet almost never stays idle for the required 30 consecutive seconds.
  **Investigated 2026-07-28**: macOS's `ARView` exposes two double-underscore
  (undocumented Swift-interface, not officially public API) properties —
  `__enableAutomaticFrameRate: Bool` and `__preferredFrameRate: Float` — that
  looked like exactly the right lever. Tried setting
  `__enableAutomaticFrameRate = false; __preferredFrameRate = 5` at init;
  measured with `ps`/`sample` before and after — **no measurable change**
  (`commonRenderCallback` was still ~95%+ of samples, CPU still 27-33%). These
  properties are very likely ARKit-session-driven frame-pacing hooks that are
  no-ops without a real AR session, which macOS's `ARView` never has (see F1's
  own `cameraMode` finding). Reverted the experiment — not worth carrying
  fragile, non-functional SPI. Needs a plan decision instead: throttle/park
  the whole overlay window (not just its render rate) during long idle,
  accept the cost, or evaluate a SceneKit fallback (already the plan's F1
  alpha-halo escape hatch) if this remains a real ship-blocker.
- **Multi-display is single-window.** The avatar is parented to
  `overlayController.windows.first`, and F4 frames are rebased against that
  one window's origin. Roaming across displays is not implemented.
- **Mixamo assets are committed to a repo.** Mixamo's terms permit use in a
  project but not redistribution of the animation data on its own. Fine for
  an internal unreleased project; if this repo ever goes public, swapping in
  CC0 assets (Quaternius/Kenney) removes the question.
- **`climb`/`point`/`type`/`listen`/`react_drag` have no clip file** in the
  committed pack — only `idle`/`walk`/`fall`/`land`/`react_click` were
  mappable. Those states fall back to idle per `AvatarLoader`.
- **`EventReaction.jump` and `bubbleText` are not wired.** `applyEventReaction`
  has a TODO; `agent_done` summaries have nowhere to display even though
  `TextInputBubbleView.showMessage` now exists for exactly that.
- **`AvatarImportValidator` hardcodes `.usdz`** regardless of `manifest.type`,
  so a `sprites`/`video` package would be reported as entirely missing.
- **`ManifestSFXKeyCoverageTests` duplicates the dummy manifest** as a string
  literal with a keep-in-sync comment — the drift it exists to prevent.
- **Settings/avatar windows lack `isReleasedWhenClosed = false`** while being
  cached in strong properties: closing and reopening is a use-after-free path.
- **Startup does not validate that clip files exist.** `AvatarLoader` checks
  manifest keys only; `AvatarImportValidator` checks files but runs on import.
  A package with no usdz "loads" and then fails silently once per clip.
- **AX titles are localized** — Calculator's on-screen "AC" answers to `삭제`.
  ai-module's prompt work cannot assume English labels.
- **SFX fade-out-on-loop-replace** stops immediately instead of ramping down;
  needs a real sound to tune against.
- **Avatar mesh height/loop-pose validation** isn't automated — needs
  RealityKit/ModelIO plus a real fixture (`docs/avatar-spec.md`).

## Review history

- External code review across `524c70e..60e81c7`, then 9 PRs of fixes.
  Confirmed by reproduction before fixing, in rough order of severity:
  `run_shell` deadlocked past 64KB of output (`waitUntilExit` before draining
  the pipes; 200KB hung for the full 10s timeout, now 0.08s); socket messages
  mutated RealityKit off the main thread; `ToolExecutor`'s completion guard
  raced; nothing called `CharacterController.update(dt:)` so every timer was
  inert; `AppDelegate` cached a dead `BridgeConnection` forever; typing with
  workspace offline reopened the input bubble in a loop; nothing seeded the
  bundled avatar so a fresh clone had no pet; `PermissionOnboarding` was dead
  code and the app never asked for anything; hardened runtime blocked the
  microphone without `com.apple.security.device.audio-input`; ad-hoc signing
  made TCC grants expire on every rebuild; the avatar pack's non-idle files
  carry no mesh, so entity-swapping per clip made the pet vanish on its first
  step; the hitbox never followed the pet; `point_at` replied before the pet
  had moved. Two regressions of my own were caught and fixed the same way:
  a vacuous socket-file test that passed because the file had not been
  created yet, and an Accessibility prompt that fired on every launch.

- Code review at commit `57615a8` → 10 findings fixed across `bf88362` and
  `b8189fc` (listener failure handling, a real connections-array data race,
  single-instance socket guard, silent send/encode failures, unbounded
  buffer growth, double-close, a deeper SFX-key-casing bug found while fixing
  the reviewed one, required-vs-recommended clip handling, schema version
  validation, empty-screen-list safety).
- USD/RealityKit single-animation-per-file constraint found during avatar
  model sourcing research → corrected F2 design (`plan/02_pet-app.md` lines
  60/174-175 updated), `docs/avatar-spec.md` added.
- Task 13 (final module) closed a previously-tracked gap on inspection: wired
  `EventRouter.reaction(for:)` to the real `characterController`/`sfxPlayer`
  inside `AppDelegate`, which earlier updates had left as a known TODO.
- Swapping in 강상우's real animated usdz pack found `USDZAvatar` never
  applied `AvatarManifest.scale` — invisible with the ~1-unit-tall Crayon.usdz
  placeholder, but a real ~180-unit-tall Mixamo-sourced rig rendered ~100x
  oversized. Fixed in `USDZAvatar.init`; confirmed via `usdcat`/`Entity.load`
  bounds measurement and a corrected on-device screenshot.
- **Self-review pass** (byeolki asked for a full refactor + self-review):
  6 parallel reviews covering every module, then fixed across 7 commits
  (`36d6980`, `4aff2d5`, `aae181f`, `5055643`, `5dbb011`, `a40d2be`, `c1f4e87`):
  - `ToolExecutor.completeOnce`'s completion guard raced between the timeout
    closure and a handler's own (often background-queue) completion — now
    synchronized through a serial queue.
  - `BridgeServer.start()` wrote its PID lock file *before* `NWListener`
    construction; a throw there left a stale lock naming the still-alive
    process, permanently blocking every later `start()` in it.
  - Deduped `JSONValue.extractFrame`/new `extractString` across 4 handlers;
    added missing tests for `RunShellHandler`/`RunAppleScriptHandler`.
  - `USDZAvatar` cached a *failed* clip load as a permanent empty
    placeholder — now only caches on success and logs the failure.
  - `ClickThroughController` only used a global `NSEvent` monitor, which
    macOS stops delivering once the window itself starts accepting clicks —
    clicks stayed enabled forever after the cursor's first hitbox entry.
    Added a local monitor, and wired the whole class into `AppDelegate`
    using `manifest.hitbox` (decoded since F2, never consumed until now).
  - `OverlayWindowController` tore down/recreated every window on a real
    display change with no hook for consumers — the avatar stayed parented
    to the orphaned old window. Added `onWindowsRebuilt` + `USDZAvatar.
    reparent(to:screenSpaceMapper:)`.
  - `HotkeyDecisionMaker`'s `.keyDown` branch had no `isPushToTalkActive`
    guard (unlike `keyUp`/`flagsChanged`), so OS key-repeat during a held
    PTT key kept re-firing `pushToTalkDown`, sliding the hold-start time
    forward and making genuine long holds measure as too short at release.
  - Settings' Volume/Mute toggles only wrote to `UserDefaults`; `AppDelegate`
    copied them into `SFXPlayer` once at launch, so live changes had no
    effect until restart. `SFXPlayer.isMuted` also only gated *new*
    `trigger()` calls, not an already-playing loop. Both now route through
    `engine.mainMixerNode.outputVolume` live. `FocusModeObserver` (F5,
    fully implemented) was never instantiated anywhere — `autoMuteOnFocus`
    did nothing; now wired.
  - `SpeechRecognitionService.stopStreaming()` called `endAudio()`
    immediately followed by `cancel()`, aborting the task before the real
    final transcription arrived — PTT results were routinely lost. Now
    only `endAudio()` is called; a generation counter stops a late result
    from a superseded session being misdelivered into a newer one.
  - `ClickDetector.startMonitoring()` leaked its previous global monitor if
    called again without an intervening `stopMonitoring()`.
  - `AppDelegate.applyEventReaction` (and `onListenStart`/`onListenEnd`)
    constructed a fresh state instance per transition, defeating
    `CharacterController`'s reference-equality same-state guard — confirmed
    real impact: `IdleState`'s `WanderScheduler` timer reset and loop
    clip/SFX replayed on every repeated same-kind event. Now one shared
    instance per state kind, reused everywhere.
  - `AvatarManagementView.importAvatar` never created the `Avatars/`
    parent directory before `copyItem`, and folded a post-validation copy
    failure into a misleading "Failed to validate" message.
  - **Deliberately not fixed**, with reasoning: collapsing the 12 mostly-
    identical `Movement/States/*` files into one generic class (real
    duplication, but the reviewer's own finding flagged it as only worth
    doing if more states are added — high risk/low reward to do blind);
    `AvatarImportValidator.status(for:)` conflating two distinct "missing"
    reasons (cosmetic); `AppLogger`'s `ts`-vs-filename `Date()` mismatch
    across UTC midnight (cosmetic edge case); deduping
    `showSettingsWindow`/`showAvatarManagementWindow` (only 2 call sites).
- **2026-07-28 review pass** (after pulling + merging #9): 6 parallel
  reviews across every subsystem touched by the just-merged commits, ~20
  findings, fixed the ones confirmed independently by multiple reviewers
  plus a crash, in commit `c4e0df1`:
  - `JSONValue.extractPID` did `pid_t(value)` on an arbitrary JSON
    `Double` — `Int32(Double)` **traps** outside `Int32` range or on a
    non-finite value, so a single malformed `find_ui_element` dispatch
    crashed the whole process. Now degrades to `nil`.
  - `AppDelegate.pointAt()` overwrote its single pending-point ivars if a
    second `point_at` arrived before the first started walking, silently
    dropping the first dispatch's `tool_result` until `ToolExecutor`'s 15s
    timeout. Extracted a small, unit-tested `PendingPointTracker` that
    fires the superseded request's callback immediately instead.
  - `handleWindowsRebuilt()`/`summonCharacter()` set the avatar's position
    directly instead of through `CharacterBody`, leaving
    `CharacterBody.position` (what the frame loop's hitbox tracking and
    movement states read) stale — desynced hitbox, visible teleport on the
    next movement tick.
  - `ReactDragState.cursorPosition` was set *before*
    `transition(to: .reactDrag)`, which calls `enter()` and resets it to
    `nil` — the pet didn't snap to the drag-start point until the next
    `dragMoved`. Reordered the two calls at the call site.
  - `WalkOnTopState` hardcoded its walk direction to always-right
    regardless of which window edge `Climb` arrived from — climbing a
    window's right edge immediately walked the pet off the very edge it
    just climbed. Direction now resolves once, toward whichever edge is
    farther, on first entry.
  - `CharacterController`'s same-state no-op guard (added in the previous
    review pass to fix `IdleState`'s timer reset) also silently blocked
    `ReactClickState`'s own documented "replay on repeated click"
    behavior. Added an opt-in `StateHandler.restartsOnReentry` so reactive
    one-shot states can restart while ambient states like `Idle` still
    can't.
  - Manually verified on-device: the redesigned mesh-sharing `USDZAvatar`
    (one persistent mesh entity, animations extracted from other clips'
    usdz files and played on it) genuinely produces distinct, moving
    `walk` animation against the real committed asset pack — confirmed via
    `launch_app` dispatched over the real bridge socket, screenshots
    showing both continuous position change and a visibly different leg
    pose between frames. `fall`/`land`/`react_click` use the identical
    mechanism but a synthetic click aimed at the (very small, ~30px) pet
    missed its hitbox, so those weren't each individually confirmed.
  - **Left for byeolki's judgment, not fixed** (lower priority / needs a
    product decision or more invasive change): `UserInputSender`'s
    TOCTOU race between checking `hasConnectedClients` and `broadcast()`
    (could report `.sent` when nothing was actually delivered);
    `BridgeConnection`'s shared `JSONEncoder` used across concurrent
    completions from different background queues (needs a per-call
    encoder); `RunShellHandler.cancel()` only terminates the direct child
    (a backgrounded grandchild keeps the pipes open forever) and
    `runningProcess` is written/read from two queues with no lock;
    `UIElementSearch`'s deadline budget doesn't bound individual AX IPC
    calls, which can themselves hang past it
    (`AXUIElementSetMessagingTimeout` isn't set); `AvatarInstaller` treats
    "the destination directory exists" as "already installed," so a
    partial/corrupt previous copy is never repaired, and doesn't detect an
    un-pulled LFS pointer file masquerading as a real usdz;
    `overlayLocalWindows` rebases window frames by subtracting AppKit
    coordinates without `GlobalScreenSpace`'s Y-flip, currently masked
    because the overlay window is always the primary display's (origin
    `(0,0)`); `CharacterController.transition(to kind:)` silently no-ops
    on an unregistered `StateKind` with no log.

Note: every item in that "left for judgment" list above was subsequently
fixed in later commits (`UserInputSender` TOCTOU, `BridgeConnection`'s
encoder race, `RunShellHandler`'s cancel/lock issue, `AXUIElementSetMessagingTimeout`,
`AvatarInstaller`'s partial-install/LFS-pointer detection, the `overlayLocalWindows`
Y-flip, and the unregistered-`StateKind` log) plus a round of idle-CPU
investigation and GitHub Actions CI setup — see `git log` for the individual
commits; this file's narrative wasn't kept in sync with them at the time.

**2026-07-29: avatar switched from 3D usdz to 2D illustration (byeolki's
decision) + added an optional ball-toy interaction (F12).** Plan docs
(`plan/01_protocol.md` §6, `02_pet-app.md`) were updated first; this is the
code-level follow-through, plus the matching change in the `protocol` repo
(`avatar-manifest.ts` 0.1.0 -> 0.2.0, additive/non-breaking).

- **Rendering**: `PetARView` (RealityKit `ARView`) is no longer instantiated
  anywhere live — `OverlayWindowController`/`AppDelegate` now build
  `SpriteLayerView` (a plain `CALayer`-backed `NSView`, `isFlipped = true` so
  its coordinate space matches `GlobalScreenSpace` directly, no
  `ScreenSpaceMapper`-style world<->screen conversion needed) and `SpriteAvatar`
  (loads one PNG per clip, same file-stem manifest convention `usdz` used).
  `PetARView`/`USDZAvatar`/`ScreenSpaceMapper` are deliberately left in place,
  compiling and still covered by their own tests — `usdz`/`video` stay
  interface-only per the plan doc, just no longer wired into the live app.
- **Bounce motion**: `BouncePreset.swift` is pure, fully-tested squash-and-
  stretch math (idle breathing, walk bounce, land squash-recover, point/
  react_click pop, kick anticipation+impact) driven by a new
  `AvatarPlayable.updateBounce(clip:elapsed:intensity:)` (default no-op via
  protocol extension, so `USDZAvatar`/`VideoAvatar` need no changes).
  `CharacterController` now tracks `stateElapsedTime` (reset every
  transition) and calls it once a frame; `intensity` comes from
  `manifest.bounce_intensity` (`CharacterBody.defaultBounceIntensity = 0.6`
  when the manifest omits it).
- **Manifest/loader**: `AvatarManifest` gained `bounceIntensity`/`emotions`
  (both optional). `AvatarLoader.requiredClips` is now `["idle"]` only —
  `walk` moved to `recommendedClips` alongside a new `"kick"` entry.
  `AvatarImportValidator` now checks `.png` files instead of `.usdz` when
  `manifest.type == .sprites`.
- **F12 ball toy (lowest priority, optional, byeolki's spec)**: menu bar
  "Throw Ball" spawns a ball at the cursor (`BallController`, a plain
  `CAShapeLayer` circle — no art asset, drawn in code since it's a pet-app-
  bundled decoration, not a customizable avatar asset). `BallPhysics` (pure,
  tested) reuses `MovementSolver.fallStep` directly for the drop and adds one
  new bit of arithmetic — a gravity-affected fling — for the post-kick
  trajectory. New `ChaseBallState`/`KickBallState` (+ `StateKind` cases) plug
  into the existing `StateHandler` machinery unchanged; the Idle/Walk-only
  entry gate (so the pet never abandons an agent-driven task to fetch a ball)
  lives in `AppDelegate`'s `ballController.onLanded` closure, not in the
  states themselves — `CharacterController.transition(to:)`'s existing
  "any state can be interrupted" design already means an agent-driven
  transition preempts `ChaseBall`/`KickBall` with no new code.
- **Dummy avatar**: real Mixamo usdz pack removed (`git rm`, still in prior
  history); replaced with 6 PNGs (`idle`/`walk`/`fall`/`land`/`react_click`/
  `kick`) generated by a one-off script — a simple round chibi-blob mascot,
  code-drawn, ~12KB each. These are explicitly placeholders (documented as
  such in that directory's README) pending the real illustrator's assets, not
  final art. `docs/avatar-spec.md` rewritten for the PNG-based spec (old
  Blender/Mixamo/RealityKit pipeline section retired).
- Verified: full `xcodebuild test` green (376 tests, all new code TDD'd —
  `BouncePresetTests`, `SpriteAvatarTests`, `SpriteLayerViewTests`,
  `BallPhysicsTests`, `BallControllerTests`, `ChaseBallStateTests`,
  `KickBallStateTests`, plus updates to existing `AvatarManifestParsingTests`/
  `AvatarImportValidatorTests`/`StateTransitionTests`); launched the real
  built `.app` after clearing Application Support (forces a fresh dummy-avatar
  reinstall from the new bundle) and confirmed via `pgrep` it started and kept
  running without crashing.

**2026-07-29: fixed two regressions from the ground-point/2D-switch fix, both reported by byeolki after using the app with real art.** `ClickThroughController.shouldAllowClicks` still built its hitbox AABB symmetric around `characterScreenPosition` -- correct when that meant "center," wrong now that it unambiguously means the ground/feet point (the previous commit's fix). The hitbox extended half its height *below* the character into empty ground and only covered the lower half above, so clicks/drags on the pet's upper body silently fell outside it -- almost certainly what looked like "can't grab it again" and drag feeling "caught on something" (mouse-moved hit-testing toggles `ignoresMouseEvents`, so a cursor over the pet's own head was being treated as click-through mid-drag). Fixed to anchor the hitbox at the ground point and extend upward, matching the same convention. Separately, `roamableArea`'s bottom edge was the literal screen bottom -- exactly where the Dock sits, and since the Dock's window level is higher than our overlay's, the pet's lower portion rendered underneath it instead of in front, looking "buried" (byeolki's "박혀있음"). Added `DockInset` (screen `frame` vs `visibleFrame` difference) and trimmed it off `roamableArea`/spawn positions, deliberately without touching `GlobalScreenSpace`'s own screen-space model (other subsystems depend on its "primary screen frame starts at (0,0)" invariant, which `visibleFrame` doesn't preserve). 383 tests passing; verified on-device via screenshot that the pet now stands fully clear of the Dock.

**2026-07-29: Settings gets a size slider + per-emotion image mapping (byeolki's request).** Both edit the *active* avatar's `manifest.json` in place via new `AvatarManifestEditor` (load/patch/save, hardcoded to the "dummy" directory pet-app actually boots from -- there's still no live avatar-switching, only import). `AvatarPlayable` gained `updateScale(_:)` and `showEmotion(_:)` (default no-ops, `SpriteAvatar` implements both -- `updateScale` recomputes bounds from the *original* manifest hitbox each call so repeated slider drags don't compound, `showEmotion` looks up `manifest.emotions[key]` and swaps the layer's image, silently no-op'ing on an unmapped key like the sounds table does). `EventRouter.EventReaction` gained an `emotion` field wired to the canonical `happy`/`thinking`/`sad` keys (agent_done(ok=true)->happy, tool_result(ok=false)->sad, agent_thinking/await_approval->thinking) -- this is what actually makes the mapping do something, not just sit in the schema. `AvatarManagementView` (opened via "Switch Avatar…") now has a Size slider (live-applies to the running avatar through a new `AppDelegate.applyLiveAvatarScale`, which also refreshes `avatarHitboxSize` and re-pushes the character's position so its ground-point offset picks up the new height) and an Emotions section (`NSOpenPanel` file picker per emotion key, plus an "add custom emotion" field). 394 tests passing (all new logic TDD'd: `AvatarManifestEditorTests`, `SpriteAvatarTests`' new `updateScale`/`showEmotion` cases, `EventRouterTests`). Not verified via an actual click-through of the new UI -- doing that would need granting Terminal/osascript System Events accessibility access for UI scripting, which wasn't done without asking first; verification here is build success + the SwiftUI code following the same slider/NSOpenPanel patterns already shipped and working elsewhere in this same file/SettingsView.

**2026-07-29: ceiling-crawling (byeolki's request, "천장이나 기어다닐 수 있게 해줘").** `CharacterBody`/`AvatarPlayable` gained `isUpsideDown`/`setUpsideDown(_:)` following the exact same guarded-`didSet` pattern as `facing`; `SpriteAvatar` folds it into `applyTransform()` as an independent Y-only scale flip (`scaleY *= -1`) rather than a full 180deg rotation, so left/right facing keeps meaning "which way it's walking" even while upside-down instead of also reversing apparent direction. `WanderScheduler.Outcome` gained `.climbToCeiling` (weights rebalanced to 45/25/15/15: walk/climb-window/climb-ceiling/stay); `StateKind` gained `.climbToCeiling`/`.ceiling`. New `ClimbToCeilingState` (climbs straight up to `roamableArea.minY` from wherever the pet currently stands -- unlike `ClimbState`, it's not tied to any window) hands off to new `CeilingState`, which crawls along `roamableArea.minY` upside-down, reversing direction at the roamable area's left/right bounds instead of falling off (there's no "edge" to walk off of on the ceiling, only the screen's own bounds), then requests `.fall` after a timed duration. `FallState` now unconditionally resets `isUpsideDown = false` on every update -- it doesn't need to know Ceiling was the one that set it, a fall off the ceiling just always lands right-side up. `AppDelegate` registers both new states and wires `.climbToCeiling`'s wander outcome to `controller.transition(to: .climbToCeiling)`. All new logic TDD'd (`CeilingStatesTests`, `WanderSchedulerTests`/`CharacterBodyTests`/`SpriteAvatarTests` additions); 408 tests passing. Verified the built `.app` launches and keeps running without regression; did not force-trigger the ceiling outcome for a live screenshot since it's a probabilistic wander roll (15% chance per 8-30s timer, ~2min expected wait) and forcing it would mean adding debug-only UI that wasn't asked for -- confidence here comes from the FSM chain being fully unit-tested end to end (climb-up motion, ceiling-bounds reversal, upside-down flip and its reset on fall), the same standard used for the original Climb/WalkOnTop states, which also have no dedicated on-device ceiling-specific screenshot.

**2026-07-29: smoothed the sprite's procedural bounce motion (byeolki: "모션 많은건 좋은데 좀 자연스럽고 깔끔하고 부드럽게 개선해줘").** Found a real discontinuity in `BouncePreset.kick`: its two phases (anticipation squash, impact stretch) were both linear ramps that peaked *at* the phase boundary and jumped straight to the other phase's peak -- a visible snap partway through every kick. Rewrote both phases as their own sine bump (0 -> peak -> 0 across each phase's own window), so they now ease in/out and meet at identity at the boundary instead of jumping. Also smoothed `BouncePreset.walk`'s horizontal squeeze, which used `abs(sin(phase))` -- a linear fold with a derivative kink at every zero-crossing (every footfall) -- replaced with `phase * phase`, same 0-at-rest/full-at-peak range but continuous through zero. 411 tests passing (3 new: kick phase-boundary continuity, kick mid-boundary identity, walk's quadratic-not-linear falloff at a distinguishing sample point). Rebuilt and relaunched the `.app`, confirmed it still runs without regression.

**2026-07-29: fixed the ceiling-crawl actually being invisible/unclickable in practice (byeolki: "이거 화면 천장을 거꾸로 매달려 다녀야함" then "애가 움직이는게 뚝뚝 끊기면서 순간이동 하거나 이러고. 애가 잘 안 잡힘").** Three real bugs in the same-day ceiling feature, found by re-reading the geometry rather than guessing: (1) `SpriteAvatar.setScreenPosition` always offset the layer by `-height/2` (the ground-standing "extends upward from the feet" convention) with no regard for `isUpsideDown` -- on the ceiling, `position.y` is `roamableArea.minY` (the literal top pixel of the screen), so the sprite's center landed *above* y=0, entirely off-screen. Fixed to offset by `+height/2` (extends downward from the ceiling attachment point) when `isUpsideDown`. (2) `ClimbToCeilingState` climbed the character's *feet* (still right-side-up, body extending upward) all the way to `roamableArea.minY` -- meaning the head went off the top of the screen well before "arrival," so the pet visibly vanished partway up, then reappeared once `CeilingState` took over and (after fix 1) rendered it hanging -- read exactly like "뚝뚝 끊기면서 순간이동" (choppy, teleporting). Fixed by climbing to `roamableArea.minY + avatarHeight` instead, so the head reaches the ceiling right as the feet would have -- this also makes the render rect identical right before/after the upside-down flip, so it reads as an in-place turn rather than a jump. `StateContext` gained an `avatarHeight: CGFloat` field for this (mirrors how `landingY` already injects world info a state needs but doesn't own), `CharacterController.avatarHeight` kept in sync by `AppDelegate` alongside `avatarHitboxSize`. (3) `ClickThroughController.shouldAllowClicks` always built its hitbox extending *upward* from the ground point regardless of orientation -- while hanging from the ceiling the body extends *downward*, so the visibly-hanging pet's hitbox was actually off-screen above it, unclickable. Added an `isUpsideDown` parameter (default `false`, so the three existing ground-case call sites needed no change) that flips the hitbox's vertical extent to match. 415 tests passing (all three fixes TDD'd, including deliberately reverting each fix first to confirm its new test fails for the right reason). Rebuilt and relaunched; the app runs without regression. Still haven't forced the ceiling roll for a screenshot (see the previous entry's reasoning), but this time the fix is grounded in re-derived geometry (traced exactly where each offset sign came from and why it was wrong), not just "tests pass."

**2026-07-29: performance pass (byeolki: "아직도 뭔가 끊기는데 프레임이 딸리는거 마냥... 이거 떨어지다가 개빨라져서 거의 순간이동임").** Two real issues, not a guess-and-check tuning pass: (1) `MovementSolver.fallStep` had no terminal velocity -- gravity accelerated it unbounded for as long as the fall lasted, and ceiling-crawling (added earlier today) made falls dramatically longer than any window-edge fall ever was (the whole screen's height instead of one window's height), so velocity -- and therefore per-frame pixel movement -- kept climbing the longer a fall went on, eventually moving the pet dozens of px in a single frame and reading as a teleport. Added a `terminalVelocity` parameter (default 900px/s) that caps it, the same way real falling objects have a terminal velocity. (2) `AppDelegate.overlayLocalWindows(excluding:)` -- called every frame via `CharacterController.windows()`, so up to 60x/sec whenever the pet isn't idle -- called `GlobalScreenSpace.current()` fresh each time, which re-queries `NSScreen.screens` and rebuilds the whole screen-space model from scratch, for a value that only actually changes on a real display reconfiguration. `AppDelegate` already holds a `ScreenManager` that caches exactly this and only refreshes on `NSApplication.didChangeScreenParametersNotification`; switched to `screenManager?.current`. Bonus: this is also strictly more correct, since `ScreenManager.current` keeps its last-known value through a momentarily-empty screen list (e.g. mid-sleep) instead of going nil and silently dropping window-awareness for that frame. 417 tests passing (2 new for the terminal-velocity cap, TDD'd with the usual revert-first RED check). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: more movement fixes (byeolki: "아직도 뭔가 순간이동 하는것도 있고... 내가 잡고 움직이려하면 따라와야하는데. 순간이동함... 그런 창 위에는 안 올라갔으면 좋겠어").** Three more real bugs, traced rather than guessed: (1) `SpriteAvatar.setUpsideDown` flipped the visual transform immediately but never recomputed the position *offset* -- that only happened lazily, next time something called `setScreenPosition`. Right when `CeilingState` hands off to `FallState` (which resets `isUpsideDown` on entry, before its own first position update runs that same tick), there was exactly one frame where the flip was already correct but the layer was still positioned with the old orientation's offset -- a visible pop reading as a stutter/teleport, and very likely what made *dragging* look broken too if the grab happened while/just after the pet was on the ceiling. Fixed by caching the last logical position and immediately re-applying `setScreenPosition`'s offset inside `setUpsideDown`, not just the transform. (2) Only `FallState` ever reset `isUpsideDown`, but the FSM allows any state to interrupt any other (a click, a drag, an agent command) -- grabbing the pet directly off the ceiling into `ReactDrag` skipped Fall's reset entirely, leaving the character rendered upside-down/offset while being dragged. Added `StateHandler.preservesUpsideDown` (default `false`, `CeilingState` overrides `true`) and centralized the reset into `CharacterController.enterCurrentState()`, so *any* transition away from Ceiling comes back right-side-up, not just the Fall-shaped one. (3) `WalkState` auto-climbs any window blocking its path with no regard for how tall it is -- a window whose top edge doesn't leave a full avatar-height of headroom (near-fullscreen/maximized) got climbed anyway, clipping the character's head off the screen exactly like the ceiling bug did. `WindowSupport.blockingWindow` gained `roamableTop`/`avatarHeight` parameters (defaulted so no other caller's behavior changes) that exclude such windows from being treated as blocking at all -- the pet now just walks past them instead. 420 tests passing (all three TDD'd, including a new `CharacterControllerTests`-style transition test in `StateTransitionTests.swift`). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: click hitbox padding (byeolki: "캐릭터 잡을때 히트박스가 너무 작아서 잘 안 잡힘").** The manifest hitbox (130x133) exactly matches the rendered sprite size -- there was no slack, so grabbing the pet needed near pixel-perfect precision on a fairly small on-screen target. `ClickThroughController.shouldAllowClicks` now adds a 40px margin on every side beyond the actual hitbox (`hitTestPadding`) before hit-testing, in both the ground and ceiling-hanging (`isUpsideDown`) orientations -- the *rendered* sprite size is untouched, only the clickable area is more forgiving. A hitbox of exactly `.zero` is still never clickable (that's an unconfigured/loading avatar, not a small one -- padding shouldn't manufacture a clickable area out of nothing). 422 tests passing (existing edge-of-hitbox tests updated to test the new padded edge instead, two new tests added for the padding boundary itself). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: fall when the window it's resting on disappears (byeolki: "창에 올려두고 화면에서 창이 없어지면 자동으로 떨어지게 해줘").** `WalkOnTopState` already re-checked its supporting window every frame, but that's not the only way the pet ends up resting on a window's top edge -- `LandingSurfaceResolver` treats window tops as valid landing surfaces, so `Fall -> Land -> Idle` (a natural fall, or a drag-and-drop) can leave the pet idling on top of a window too, and `IdleState` never checked anything. If that window later closed or minimized, the pet just stayed floating in place forever. `IdleState.update` now compares `context.landingY(position)` (what's directly below right now) against the pet's current Y each frame -- reusing the already-injected `landingY` closure, no new plumbing -- and requests `.fall` the moment a gap opens up (same `WindowSupport.footTolerance` used elsewhere for "close enough to standing on it"). Standing correctly on the floor is unaffected (`landingY(position) == position.y` there too, so no false trigger). 424 tests passing (2 new, one pre-existing test updated since it implicitly assumed "not currently falling" without setting `landingY` to match). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: hide/show button + movement-speed slider (byeolki: "숨기기 버튼이랑 이동속도 조절하는 메뉴 만들어주고").** `MenuBarController` gained a "Hide"/"Show" toggle item (label updates to reflect real state after `AppDelegate` actually hides/shows the overlay, not assumed optimistically) -- `AppDelegate.toggleCharacterVisibility` uses `orderOut`/`orderFrontRegardless` on the overlay windows (not `alphaValue`), so a hidden pet also stops receiving/dispatching mouse events, not just stops rendering; also re-applied after a display-reconfiguration window rebuild, which otherwise always re-shows every window unconditionally. `SettingsStore` gained `walkSpeedMultiplier` (persisted, default 1.0, live-update closure following the same pattern as volume/mute) and a Speed slider in the existing Settings "Movement" section (0.25x-3.0x). Threading the multiplier through required `StateContext`/`CharacterController` to gain a `walkSpeed` field (mirrors how `avatarHeight` was added) -- `Walk`/`Climb`/`ClimbToCeiling`/`MoveTo`/`ChaseBall` now pass `context.walkSpeed` explicitly to `MovementSolver.step` instead of relying on its default parameter, and `WalkOnTop`/`Ceiling` (which move by hand, not via `.step`) reference `context.walkSpeed` instead of the `MovementSolver.walkSpeed` constant directly. 434 tests passing (7 new -- one per state that now respects a custom speed, plus `SettingsStore`'s round-trip/default/live-update tests). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: roamableArea now updates on fullscreen Space switches (byeolki: "전체화면 되면 dock위가 아니라 화면 위로 다니게 바꿔줘").** `OverlayWindow` already had `.fullScreenAuxiliary` in its collection behavior, so it was already following the user into a fullscreen app's Space -- but `roamableArea`'s Dock-trimmed height (`groundAwareSize`) was only ever computed once, at initial setup and on real display reconfiguration. A fullscreen Space doesn't reserve any Dock strip at all (`NSScreen.visibleFrame` reports no inset there), but nothing re-checked that after setup, so the pet's floor stayed pinned at "regular-desktop height minus Dock" even while roaming over a fullscreen app, leaving an unused gap at the true bottom of the screen. Space switches don't fire `didChangeScreenParametersNotification` (that's for actual display reconfiguration), so added a dedicated `NSWorkspace.activeSpaceDidChangeNotification` observer that recomputes `roamableArea` on every Space change. No new state-machine logic needed for the pet to actually settle onto the new (taller, in this case) floor -- the `IdleState` "supporting surface disappeared" check added earlier this session (`landingY(position) > position.y`) already handles that generically. 437 tests passing (unchanged -- this is `AppDelegate` observer wiring, consistent with how `ScreenManager`'s own live `NSScreen` observer isn't unit tested either; the pure math it calls, `DockInset.bottomInset`, already has coverage). Rebuilt, relaunched, confirmed no regression. Also rebased/merged a teammate's unrelated `f6f2921` (ToolExecutor per-tool timeout fix) that landed on `main` mid-session.

**2026-07-29: wall-climbing rotates the sprite too (byeolki: "그리고 벽 타는 것도 사진 돌려서 올라가게 해주고").** `SpriteAvatar.updateBounce` now derives `isClimbing` from the clip name it's already given every frame (`clip == "climb"`) and rotates the sprite 90deg in `applyTransform` while it's true -- no new `AvatarPlayable` method or `StateContext` field needed, since both `ClimbState` (a window's side) and `ClimbToCeilingState` (open air, toward the ceiling) already share the `"climb"` clipKey and get the rotation for free. Doesn't track which side of a window is being climbed (there's no existing signal for that), so the rotation direction is fixed rather than mirrored per side -- a simpler match for what was actually asked ("사진 돌려서 올라가게," not "rotate correctly per side"). 440 tests passing (3 new: rotates on the climb clip, doesn't rotate on other clips, resets when leaving the climb clip). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: closed the other path onto an unclimbable window (byeolki: "그런 창들은 위에 못 올라가게 해줘").** The earlier fix only stopped `WalkState` from *climbing* into a window too tall to stand on without clipping -- but `LandingSurfaceResolver` (what `FallState` actually lands on) had no such check at all, so the pet could still end up clipped on top of one via any OTHER path that routes through Fall (a drag-and-drop, falling off the ceiling, falling past a smaller window onto a bigger one below it). `LandingSurfaceResolver.landingY` gained the same `roamableTop`/`avatarHeight` parameters as `WindowSupport.blockingWindow` (defaulted so no other caller's behavior changes) -- a window that doesn't leave a full avatar-height of headroom above its top edge is now excluded from the landing-surface candidates entirely, so the pet falls straight through to whatever's actually safe to stand on. `AppDelegate`'s `controller.landingY` closure (the single place `LandingSurfaceResolver.landingY` is ever called from) now passes both through. 442 tests passing (2 new: excluded when too tall, still a candidate with enough headroom). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: short falls (off a window) felt much slower than long drops (byeolki: "이새끼 창위에 있다가 떨어지는 속도가 너무 느림. 내가 잡아서 위에서 놓아서 떨어지는 속도랑 너무 다름").** Both paths use identical `FallState` physics (always starting from rest), so the discrepancy wasn't a separate bug -- it's that reaching `terminalVelocity` (900px/s, tuned down earlier this session specifically because ceiling-height falls were too fast) took ~340px of falling at the old gravity (1200px/s²). A manual drop from up near the top of the screen easily covers that distance and spends real time at full speed; a fall off a typical window's top edge often doesn't, so it stays visibly "floaty" for its whole (short) duration even though the underlying physics is the same. Raised gravity to 2400px/s² (halves the ramp-up distance to terminal velocity, ~170px) rather than touching `terminalVelocity` itself, which was deliberately tuned down to fix the *previous* "ceiling falls look like teleporting" complaint -- this way short falls reach the same already-tuned top speed much sooner, without long falls exceeding it. 443 tests passing (1 new, pinning the live default gravity/terminalVelocity combination to reach full speed within roughly a window's height of falling, not just the math in isolation). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: dragging eased instead of snapping to the cursor (byeolki: "내가 잡고 움직일때 아직 움직임이 부자연스러워").** `ReactDragState` previously assigned `context.body.position = cursorPosition` outright every frame -- a deliberate original choice ("anything else feels like lag"), but combined with `react_drag`'s bounce preset being `.none` (zero procedural motion), the pet was perfectly rigid and teleported exactly onto the cursor every single frame, which read as unnatural rather than "responsive." Added `MovementSolver.ease(from:toward:rate:dt:)` -- a frame-rate-independent exponential ease (`1 - exp(-rate * dt)` of the remaining distance closed per frame, so it converges to the same place regardless of how a given span of time was split into frames) -- and switched `ReactDragState` to ease toward the cursor instead of snapping to it. Tuned to converge within roughly 100-150ms, fast enough to stay responsive rather than laggy, but leaves enough "give" to no longer read as a rigid teleport. 447 tests passing (3 new for `ease` itself, 2 updated + 1 new for `ReactDragState` -- the old tests asserted exact-position-after-one-tiny-timestep, which no longer holds by design, so they now run long enough for the ease to converge and assert accuracy-bounded equality instead). Rebuilt, relaunched, confirmed no regression.

**2026-07-29: two more interactions -- petting + a juggle-before-kick (byeolki: "좀 더 다양한 모션과 상호작용(축구공, 등등)을 추가해줘").** Scoped the open-ended ask into two concrete, well-tested additions rather than a sprawl.

**Petting (double-tap):** `PetGestureRecognizer` gained double-tap detection -- a completed tap seeds a short window (position + time thresholds), and a second tap landing inside it fires `.doubleTapped` instead of `.tapped` (the first tap still fires its own `.tapped`/ReactClick first, immediately interrupted by the petting reaction if the second tap follows fast enough -- an acceptable simplification that keeps the recognizer a synchronous, timer-free value type, same constraint the file's header already documents). New `PettingState` (mirrors `ReactClickState`'s exact shape) plays a new `BouncePreset.wiggle` -- several quick side-to-side pulses that decay to identity, distinct from `react_click`'s single "pop" -- and shows the `happy` emotion if the user has mapped one in Settings.

**Juggle-before-kick:** `ChaseBallState` now hands off to a new `JuggleBallState` (not directly to `KickBall`) -- `BallPhysics.juggle(_:)` pops a resting ball straight up by reusing the exact `.falling`->`.resting` arc a drop already takes (an upward initial velocity just decelerates under gravity, peaks, and falls back via identical math -- no new physics needed). `JuggleBallState` fires a configurable number of pops (default 2) within a single state entry via an internal timer, rather than re-entering itself per bounce, sidestepping the need to distinguish "fresh start from ChaseBall" from "continuing the count" that re-entering the same `StateHandler` instance would require.

Updated `plan/02_pet-app.md`'s transition table and F12 section to match (also folded in `ClimbToCeiling`/`Ceiling`/`Petting` to the state list, which an earlier same-day change had left out of sync).

466 tests passing (19 new: 6 double-tap detection, 3 wiggle bounce math, 2 `PettingState` timing, 2 `BallPhysics.juggle`, 2 `BallController.juggle()`, 4 `JuggleBallState`). Rebuilt, relaunched, confirmed no regression.
