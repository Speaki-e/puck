# pet-app progress

Live status tracker for implementation work. Updated as tasks complete —
check here instead of asking for a status recap. Full design rationale is in
[`docs/directory-structure.md`](docs/directory-structure.md); implementation
order (P0-P9) is defined in `plan/02_pet-app.md` section 2.

**Last updated:** 2026-07-27 · **Tests:** 130 passing (`xcodebuild test`) · **Latest commit:** `380d750`

**Manually verified end-to-end on-device:** built the app, launched it, screenshotted the real screen — a usdz model rendered transparently over other windows via the overlay pipeline (window + RealityKit + USDZAvatar all working together, not just compiling). Used a local Apple-provided usdz (Crayon.usdz from the Xcode/iOS-Simulator install) as a placeholder in `~/Library/Application Support/PetAgent/Avatars/dummy/` — never committed to the repo. The real per-clip avatar assets (idle.usdz/walk.usdz/... with actual walk animation) are still 강상우's pending work; this only confirms the rendering pipeline itself.

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
| P2 | F3 on-screen movement, multi-display | [~] FSM skeleton + coordinate math done; per-state movement logic (Walk/Climb/etc. actual motion) still TODO, blocked on F4 live wiring |
| P3 | F4 level 1 + moving on top of windows | [x] level 1 done (`WindowListWatcher`, `LandingSurfaceResolver`, `AccessibilityPermission`); state-machine wiring to F4 still TODO |
| P4 | F5 SFX | [x] done |
| P5 | F6 global hotkeys + text input | [ ] not started |
| P6 | F7 PTT+STT | [ ] not started |
| P7 | socket server + F11 executor | [x] done (`BridgeServer`, `BridgeConnection`, `EventRouter`, `ToolExecutor`, 5/8 handlers) |
| P8 | F4 level 2 + F10 pointing | [ ] not started (`UIElementInspector`, `Pointing/`, `FindUIElementHandler`, `PointAtHandler`) |
| P9 | F10 click_element, avatar-switch UI | [ ] not started (`SyntheticClick`, `Settings/AvatarManagementView`, `ClickElementHandler`) |

Order was reshuffled versus the plan doc's literal P0-P9 sequence to front-load
modules that don't depend on rendering (F1) — see
`docs/directory-structure.md` section 4 for the mapping.

## Detail by module

| Module | Files | Tests | Notes |
|---|---|---|---|
| Bridge (F11/socket) | `BridgeMessages`, `JSONValue`, `BridgeServer`, `BridgeConnection`, `EventRouter` | 44 | Real end-to-end UDS socket test (no mocks). Listener-failure detection, single-instance guard, buffer cap all added post-review. |
| Avatar (F2) | `AvatarManifest`, `AvatarLoader`, `AvatarPlayable`, `AvatarImportValidator`, `USDZAvatar` | 26 | **Design correction**: one usdz per clip, not one shared usdz (RealityKit only plays a usdz's first animation) — see `docs/avatar-spec.md`. Validator checks clip-file existence + size budget; mesh height/scale/loop still manual. `USDZAvatar` implemented and manually verified rendering a real usdz on-device. `VideoAvatar`/`SpriteAvatar` still stubs (later priority per plan). |
| Movement (F3) | `CharacterController`, `GlobalScreenSpace`, `WanderScheduler`, `StateHandler`, 12 states | 20 | FSM skeleton + coordinate normalization done; per-state movement math (actual walking/climbing/falling) still TODO, needs F1/F4 live data. |
| WindowSensing (F4 level 1) | `WindowInfo`, `WindowListWatcher`, `LandingSurfaceResolver`, `AccessibilityPermission` | 12 | Level 2 (`UIElementInspector`, `ScreenCaptureFallback`) not started. |
| Tools (F11) | `ToolExecutor`, `ToolExecutionLogger`, 5/8 handlers | 9 | `LaunchAppHandler`, `ListRunningAppsHandler`, `GetFrontmostWindowHandler`, `RunShellHandler`, `RunAppleScriptHandler` real. `FindUIElementHandler`/`PointAtHandler`/`ClickElementHandler` blocked on F4-level-2/F10. |
| Overlay (F1) | `OverlayWindow`, `OverlayWindowController`, `ScreenManager`, `ScreenSpaceMapper`, `ClickThroughController`, `PetARView` | 20 | One window+`PetARView` per real display, positioned via AppKit frames (not the normalized FSM-logic space). Found/fixed a real API bug: macOS's `ARView` has no `cameraMode`/`automaticallyConfigureSession` at all (no camera-passthrough AR on Mac) — plan doc corrected. Alpha-halo mitigation steps 2-4 and idle frame-rate downshift need a real avatar to evaluate against; not implemented speculatively. |
| Audio (F5) | `SFXPlayer`, `PlayerNodePool`, `SoundTable`, `FocusModeObserver` | 12 | `SFXTriggering` protocol gained a `loop` param (symmetric with `AvatarPlayable.play`) so F5 knows which triggers should loop. Fade-out-on-loop-replace stops immediately for now (documented TODO, needs a real sound to tune a volume ramp against). `FocusModeObserver` is explicitly best-effort/unverified on modern macOS — see its doc comment. |
| Input (F6) | — | 0 | Not started. |
| Voice (F7) | — | 0 | Not started. |
| Pointing (F10) | — | 0 | Not started. |
| Settings/Diagnostics/App bootstrap | `PetAgentApp`/`AppDelegate` | 0 | `AppDelegate` now wires ScreenManager -> OverlayWindowController -> AvatarLoader -> USDZAvatar -> CharacterController(IdleState) — enough to show a static/idle avatar with zero permissions. `PermissionOnboarding`, `BridgeServer`, `GlobalHotkeyManager` wiring still pending. |

## Known gaps / blocked items

- **`await_approval` has no manifest sound key.** `EventRouter` produces this
  SFX key but the `protocol` repo's manifest schema (section 6) doesn't define
  it yet, and `protocol` has no commits to PR against. Tracked (not silently
  patched) by `ManifestSFXKeyCoverageTests`.
- **Avatar mesh height/scale/loop-pose validation** isn't automated yet —
  needs RealityKit/ModelIO plus a real usdz fixture, both of which arrive
  with P0 (Overlay). Manual verification until then (`docs/avatar-spec.md`).
- **No real avatar assets** — `Resources/Avatars/dummy/manifest.json` exists;
  the actual per-clip `.usdz`/`.wav` files are still pending (owner: 강상우).

## Review history

- Code review at commit `57615a8` → 10 findings fixed across `bf88362` and
  `b8189fc` (listener failure handling, a real connections-array data race,
  single-instance socket guard, silent send/encode failures, unbounded
  buffer growth, double-close, a deeper SFX-key-casing bug found while fixing
  the reviewed one, required-vs-recommended clip handling, schema version
  validation, empty-screen-list safety).
- USD/RealityKit single-animation-per-file constraint found during avatar
  model sourcing research → corrected F2 design (`plan/02_pet-app.md` lines
  60/174-175 updated), `docs/avatar-spec.md` added.
