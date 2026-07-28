# pet-app progress

Live status tracker for implementation work. Updated as tasks complete —
check here instead of asking for a status recap. Full design rationale is in
[`docs/directory-structure.md`](docs/directory-structure.md); implementation
order (P0-P9) is defined in `plan/02_pet-app.md` section 2.

**Last updated:** 2026-07-28 · **Tests:** 307 passing (`xcodebuild test`) · **`main`:** `c4e0df1`

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
  + `detail` landed with tests in the same pass). What remains is purely
  transcription: write `types/` + `swift/` in the protocol repo from
  `plan/01_protocol.md` and the shipped Swift.
- **CPU while idle is ~31%, and the plan's fix does not address it.**
  `sample` puts essentially all of it in `ARView.commonRenderCallback()` —
  RealityKit renders on its own display-linked loop regardless of FSM tick
  rate, so `IdleFrameRatePolicy` (F1's 60→15 downshift) changes nothing
  measurable. It also barely engages: F3's wander timer fires every 8-30s, so
  the pet almost never stays idle for the required 30 consecutive seconds.
  Needs a plan decision — throttle/park the ARView, lower the threshold, or
  wander less.
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
