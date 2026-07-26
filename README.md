# pet-app

macOS desktop pet app (Swift). Owns pet rendering/movement, the system tool
executor, and voice/text input. This is the main-app repo of the `Speaki-e`
project (codename PetAgent); the overall picture lives in
`plan/프로젝트_개요.md`, and this repo's detailed plan is `plan/02_pet-app.md`.

- **Independence principle**: even without a local socket connection to
  `workspace`, this must fully function as a pure desktop pet.
- **Dependency contract**: only references the `protocol` repo (socket
  schema, tool registry, avatar manifest schema); never references other
  repos' code directly.
- **Avatar/sound resources** are produced/supplied outside the team. This repo
  only consumes avatar packages that satisfy `protocol`'s manifest schema, and
  includes just one dummy avatar for development.

## Ownership

| Person | Modules |
|---|---|
| 강상우 (Sangwoo Kang) | F1 transparent overlay rendering, F2 avatar loader, F5 SFX, avatar import spec validator |
| 박해영 (Haeyoung Park) | F3 movement FSM, F4 window sensing, F6 global hotkeys, F7 PTT+STT, F10 pointing, F11 system tool executor |

## Current status

The feature-oriented folder structure is in place, and modules that don't
depend on rendering (F1) are being implemented first. See
[`docs/directory-structure.md`](docs/directory-structure.md) for the full
structure, design rationale, and implementation order.

The Xcode project (`.xcodeproj`) is not committed — it's generated from
`project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen). When
changing the target structure, don't touch the project file directly in
Xcode; edit `project.yml` and regenerate instead (avoids `project.pbxproj`
merge conflicts).

## Clone -> run

1. `brew install xcodegen` (if you don't have it).
2. From the repo root, run `xcodegen generate` — this creates
   `PetAgent.xcodeproj` and `PetAgent/Resources/Info.plist`.
3. Open `PetAgent.xcodeproj` in Xcode 15+.
4. Grant the TCC permissions requested on first launch: Accessibility
   (hotkeys/UI inspection/synthetic clicks), microphone, speech recognition,
   Screen Recording (optional, fallback only).
5. Build and run — it should work immediately with the dummy avatar in
   `PetAgent/Resources/Avatars/dummy/`, with no socket connection required
   (per the M-A milestone).
6. Running the `workspace` repo alongside it connects them over a local Unix
   socket (`~/Library/Application Support/PetAgent/bridge.sock`).

To just build/test from the CLI:
`xcodebuild -project PetAgent.xcodeproj -scheme PetAgent build` /
`xcodebuild -project PetAgent.xcodeproj -scheme PetAgent test`.

## Stack summary

Swift 5.10+ / macOS 14+, AppKit (menu-bar resident, LSUIElement) + RealityKit
(ARView `.nonAR`, USDZ), CGWindowList + AXUIElement (window sensing),
CGEvent.tapCreate (global input), SFSpeechRecognizer (STT), AVAudioEngine
(SFX), Network.framework `NWListener` (UDS socket server). Details in
`plan/02_pet-app.md` section 4.

## Docs

- [`docs/directory-structure.md`](docs/directory-structure.md) — directory
  structure draft and design rationale
- [`docs/qa-cases.md`](docs/qa-cases.md) — per-milestone QA scenarios
- `plan/02_pet-app.md`, `plan/01_protocol.md`, `plan/프로젝트_개요.md` — the
  upper-level planning docs (Speaki-e repo)
