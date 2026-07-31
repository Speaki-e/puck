//
//  AppDelegate.swift
//  Shaydi
//
//  Shared · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Coordinates the init order: permission self-check -> overlay -> bridge
//  server -> global hotkeys.
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, IdleWanderDelegate, PetPointingCoordinating {
    private let settingsStore = SettingsStore()

    private var screenManager: ScreenManager?
    private var overlayController: OverlayWindowController?
    private var characterController: CharacterController?
    private var avatar: SpriteAvatar?
    private var sfxPlayer: SFXPlayer?
    private var clickThroughController: ClickThroughController?
    /// byeolki's request, 2026-07-29: menu bar Hide/Show toggle.
    private var isCharacterHidden = false
    private var spaceChangeObserver: NSObjectProtocol?
    private var avatarHitboxSize: CGSize = .zero
    /// Unscaled manifest.hitbox -- recomputes avatarHitboxSize when Settings'
    /// size slider live-applies a new scale (applyLiveAvatarScale).
    private var baseHitboxSize: CGSize = .zero
    private var characterBody: CharacterBody?
    private let pendingPointTracker = PendingPointTracker()
    private var focusModeObserver: FocusModeObserver?

    /// OverlayWindowController creates one window per display, but every
    /// ground/roamable/click-through computation in this file is scoped to
    /// a single display -- multi-monitor support is not implemented, this
    /// just names the existing single-display assumption in one place
    /// instead of repeating `overlayController?.windows.first` at each site.
    private var primaryWindow: NSWindow? { overlayController?.windows.first }

    // One shared instance per FSM state, reused for every transition into it.
    // CharacterController.transition's same-state no-op guard is reference
    // equality (StateHandler: AnyObject) -- constructing a fresh instance per
    // transition (e.g. `IdleState()` each time) defeated that guard, silently
    // resetting IdleState's WanderScheduler timer and replaying loop clip/SFX
    // on every repeated same-kind event.
    private let idleState = IdleState()
    private let walkState = WalkState()
    private let climbState = ClimbState()
    private let walkOnTopState = WalkOnTopState()
    private let fallState = FallState()
    private let landState = LandState()
    private let moveToState = MoveToState()
    private let typeState = TypeState()
    private let pointState = PointState()
    private let listenState = ListenState()
    private let reactClickState = ReactClickState()
    private let reactDragState = ReactDragState()
    // Double-tap "petting" interaction (2026-07-29, more interactions).
    private let pettingState = PettingState()
    private let spinState = SpinState()
    // F13 (2026-07-29): Option+Shift+Space pins the character while the
    // client window is open, same "capture then restore" pattern as
    // stateBeforeListen below.
    private let pinnedState = PinnedState()
    private var stateBeforePin: StateHandler?
    /// Recognises the cursor being rubbed over the pet's head. Owned here
    /// rather than by ClickThroughController so that type stays about hit
    /// testing, matching how gesture -> FSM mapping already works.
    private var headPetDetector = HeadPetDetector()
    /// Where the toy sat relative to the cursor when it was picked up.
    private var toyGrabOffset: CGPoint = .zero
    /// How far above the pet's head a spun toy floats.
    private static let spinHoverGap: CGFloat = 14

    /// The toy's throw speed, measured the same way the pet's is.
    private var toyThrowVelocity = CursorVelocityTracker()
    /// Mouse events don't arrive on a clock, so the tracker's dt comes from
    /// the gap between them.
    private var lastToyDragTime: TimeInterval?
    // F3 ceiling-crawling (2026-07-29): WanderScheduler's .climbToCeiling outcome.
    private let climbToCeilingState = ClimbToCeilingState()
    private let ceilingState = CeilingState()
    // F12 (optional, lowest priority): ball-toy interaction.
    private let chaseBallState = ChaseBallState()
    private let juggleBallState = JuggleBallState()
    private let kickBallState = KickBallState()
    /// Every toy that's out, and which one the pet is playing with. The FSM
    /// states above still only ever deal with one toy -- `toyBox.focused`.
    private var toyBox: ToyBox?
    /// When the pet last finished playing. Play used to restart the instant
    /// the thrown toy settled, so a toy left out meant the pet did nothing
    /// else ever again (byeolki: "장난감을 너무 많이 가지고 놀진 않게 약간
    /// 시간을 가지게", 2026-07-30).
    private var toyPlayEndedAt: TimeInterval?
    /// How long the pet goes without picking a toy up again. Long enough for
    /// a wander or two in between, short enough that a toy put out for it
    /// doesn't feel ignored.
    static let toyPlayCooldown: TimeInterval = 20
    /// Had enough of toys for the moment.
    private var isRestingFromToys: Bool {
        guard let toyPlayEndedAt else { return false }
        return CACurrentMediaTime() - toyPlayEndedAt < Self.toyPlayCooldown
    }
    /// The toy the cursor picked up, decided once on mouse-down. Held for the
    /// whole gesture for the same reason ClickThroughController holds its
    /// subject: the toy moves while being dragged, so re-testing per event
    /// could hand the rest of the drag to a different one.
    private var grabbedToy: BallController?

    private let frameClock = FrameClock()
    private var idleFrameRate = IdleFrameRatePolicy()
    // Shared: PointAtHandler starts a pointing session on it, and the frame
    // clock ticks the same instance so the release timeout can elapse.
    private let pointingController = PointingController()

    private var windowListWatcher: WindowListWatcher?
    private var toolExecutor: ToolExecutor?

    private var bridgeServer: BridgeServer?
    private var bridgeMessageRouter: BridgeMessageRouter?
    /// Still used directly by voice/PTT (F7) -- the F13 client window that
    /// used to also route through this moved out to ShaydiAgent, its own
    /// process, as of 2026-07-30.
    private lazy var userInputSender = UserInputSender { [weak self] in self?.bridgeServer }

    private var hotkeyManager: GlobalHotkeyManager?
    private var voiceInputController: VoiceInputController?
    private var stateBeforeListen: StateHandler?

    private var menuBarController: MenuBarController?
    private var textInputBubbleWindow: TextInputBubbleWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only ever one pet: a second launch (double-click, or a Debug build
        // next to an installed copy -- same bundle id either way) quits
        // itself instead of stacking a second character and menu bar item.
        // Not under XCTest -- the test runner hosts this same app, and the
        // guard tripping on an already-running pet kills the whole test run.
        let processInfo = ProcessInfo.processInfo
        let isHostingTests = processInfo.environment["XCTestSessionIdentifier"] != nil
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.speaki-e.Shaydi")
        if !isHostingTests, peers.contains(where: { $0.processIdentifier != processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }

        requestPermissions()

        // byeolki: "둘이 같이 가야하는거임" -- ShaydiAgent (the F13 client
        // window, now a separate Dock-resident app) is useless without this
        // process hosting bridge.sock, so each launches the other.
        CompanionAppLauncher.launchIfNeeded(bundleIdentifier: "com.speaki-e.ShaydiAgent")

        setUpMenuBar()
        setUpOverlayAndAvatar()
        setUpWindowSensing()
        setUpToolExecutor()
        setUpBridgeServer()
        setUpGlobalHotkeys()
        setUpFrameLoop()
        setUpSpaceChangeObserving()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Everything started in applicationDidFinishLaunching gets torn down
        // here. BridgeServer is the one that matters beyond this process:
        // stop() removes the lock file and unlinks the socket, and skipping it
        // left a lock file naming this (now dead) PID in Application Support.
        // A dead PID is currently recovered from at next launch, but if the OS
        // recycles that PID onto any live process, start() refuses forever with
        // .alreadyRunning and nothing tells the user which file to delete.
        frameClock.stop()
        hotkeyManager?.stop()
        voiceInputController?.pushToTalkUp()
        bridgeServer?.stop()
        windowListWatcher?.stop()
        focusModeObserver?.stopObserving()
        clickThroughController?.stopMonitoring()
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
    }

    // MARK: - Permissions

    /// PermissionOnboarding existed but nothing ever called it: launch only
    /// logged `currentStatus()` and moved on, so the app never asked for
    /// anything. Microphone and speech recognition stayed `notDetermined`
    /// forever — VoiceInputController would try to record and fail silently —
    /// and Accessibility could only be granted by hand, which is exactly the
    /// flow that breaks on stale System Settings entries.
    private func requestPermissions() {
        AppLogger.shared.log(.info, "Launch permission status: \(PermissionOnboarding.currentStatus())")

        // Only prompts the ones still undecided; already-answered permissions
        // (granted or denied) are left alone rather than re-asked every launch.
        PermissionOnboarding.requestUndecidedPermissions { status in
            AppLogger.shared.log(.info, "Permission status after prompting: \(status)")
        }

        // Accessibility can't be requested silently — the only way to ask is
        // macOS's own modal. Ask once and then stay quiet: prompting on every
        // launch means anyone who dismisses it, or who is part-way through
        // granting it in System Settings, gets the dialog again next time.
        // Settings has a button for granting it later.
        if PermissionPromptPolicy.shouldPromptForAccessibility(
            isTrusted: AccessibilityPermission.isTrusted(prompt: false),
            hasAskedBefore: settingsStore.hasRequestedAccessibility
        ) {
            settingsStore.hasRequestedAccessibility = true
            _ = AccessibilityPermission.isTrusted(prompt: true)
        }
    }

    // MARK: - Menu bar

    private func setUpMenuBar() {
        let menuBar = MenuBarController()
        menuBar.makePopoverContent = { [weak self] in self?.makeSettingsPanel() }
        menuBar.onOpenClient = { [weak self] in self?.openClientApp() }
        menuBarController = menuBar
    }

    /// The panel the status item drops (byeolki, 2026-07-31: "이 설정 이거
    /// 위에 아이콘 누르면 바로 나오게"). Rebuilt per open so it reflects live
    /// state -- which toys are out, whether the pet is hidden, whether
    /// Accessibility has been granted since last time.
    private func makeSettingsPanel() -> NSViewController {
        let view = SettingsView(
            store: settingsStore,
            onAvatarScaleChanged: { [weak self] scale in self?.applyLiveAvatarScale(scale) },
            initialToysOut: toyBox?.outToyNames ?? [],
            onToggleToy: { [weak self] toy in self?.toggleToy(toy) ?? [] },
            initialIsCharacterHidden: isCharacterHidden,
            onOpenClient: { [weak self] in
                // Closed first: the client app comes forward, and leaving the
                // panel floating over it reads as a stuck window.
                self?.menuBarController?.closePopover()
                self?.openClientApp()
            },
            onToggleVisibility: { [weak self] in self?.toggleCharacterVisibility() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        return NSHostingController(rootView: view)
    }

    /// byeolki's request, 2026-07-29: hide/show the pet without quitting the
    /// app. orderOut/orderFrontRegardless rather than alphaValue -- an
    /// ordered-out window also stops receiving/dispatching mouse events, so
    /// there's nothing left to click on a hidden pet either.
    private func toggleCharacterVisibility() {
        isCharacterHidden.toggle()
        for window in overlayController?.windows ?? [] {
            if isCharacterHidden {
                window.orderOut(nil)
            } else {
                window.orderFrontRegardless()
            }
        }
    }

    // MARK: - Overlay + avatar (F1/F2/F3/F5)

    private func setUpOverlayAndAvatar() {
        guard let screenManager = ScreenManager() else { return }
        self.screenManager = screenManager

        let overlayController = OverlayWindowController(screenManager: screenManager)
        overlayController.onWindowsRebuilt = { [weak self] in self?.handleWindowsRebuilt() }
        overlayController.start()
        self.overlayController = overlayController

        guard
            let window = overlayController.windows.first,
            let spriteView = window.contentView as? SpriteLayerView
        else {
            return
        }

        let avatarsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shaydi/Avatars", isDirectory: true)
        let avatarDirectory = avatarsDirectory.appendingPathComponent("dummy", isDirectory: true)

        // First run has nothing in Application Support yet; seed the bundled
        // package so a fresh clone shows a pet instead of an empty screen.
        if let bundled = Bundle.main.url(forResource: "Avatars/dummy", withExtension: nil) {
            let outcome = AvatarInstaller.installIfNeeded(bundledPackage: bundled, intoAvatarsDirectory: avatarsDirectory)
            AppLogger.shared.log(.info, "Bundled avatar install: \(outcome)")
        } else {
            AppLogger.shared.log(.warning, "No bundled avatar package in the app bundle")
        }

        let loadResult: AvatarLoadResult
        do {
            loadResult = try AvatarLoader.load(avatarDirectory: avatarDirectory)
        } catch {
            // Keep the specific reason (missing required clips, unsupported
            // schema version, undecodable manifest) — `try?` threw away the
            // distinction AvatarLoaderError exists to make.
            AppLogger.shared.log(.error, "Failed to load dummy avatar at \(avatarDirectory.path): \(error)")
            return
        }

        // manifest.hitbox scaled by manifest.scale -- must be computed before
        // controller.avatarHeight below, which the FSM's climb/land/wander
        // logic depends on being non-zero from the very first frame (found
        // via review: this used to read the .zero default here because the
        // computation used to happen after controller setup instead of
        // before it).
        let scale = loadResult.manifest.scale
        baseHitboxSize = CGSize(width: loadResult.manifest.hitbox.width, height: loadResult.manifest.hitbox.height)
        avatarHitboxSize = CGSize(width: baseHitboxSize.width * scale, height: baseHitboxSize.height * scale)

        let avatar = SpriteAvatar(
            avatarDirectory: avatarDirectory,
            loadResult: loadResult,
            parent: spriteView.contentLayer
        )
        let initialPosition = GroundedSpawnPosition.position(in: groundAwareSize(of: window))
        avatar.setScreenPosition(initialPosition)
        self.avatar = avatar

        let soundTable = SoundTable(avatarDirectory: avatarDirectory, sounds: loadResult.manifest.sounds)
        let sfxPlayer = SFXPlayer(soundTable: soundTable)
        sfxPlayer.volume = settingsStore.volume
        sfxPlayer.isMuted = settingsStore.isMuted
        self.sfxPlayer = sfxPlayer

        // Previously copied once at launch only -- Settings' Volume/Mute
        // toggles had no live effect on a running session until restart.
        settingsStore.onVolumeChanged = { [weak sfxPlayer] volume in sfxPlayer?.volume = volume }
        settingsStore.onMuteChanged = { [weak self, weak sfxPlayer] isMuted in
            sfxPlayer?.isMuted = isMuted
            guard isMuted else { return }
            self?.showMutedComplaint()
        }
        settingsStore.onToyScaleChanged = { [weak self] scale in
            self?.toyBox?.updateScale(scale)
        }
        settingsStore.onWalkSpeedMultiplierChanged = { [weak self] multiplier in
            self?.characterController?.walkSpeed = MovementSolver.walkSpeed * multiplier
        }
        // autoMuteOnFocus existed as a setting with nothing acting on it --
        // FocusModeObserver was implemented but never instantiated anywhere.
        let focusObserver = FocusModeObserver()
        focusObserver.onChange = { [weak self, weak sfxPlayer] isFocusActive in
            guard let self, self.settingsStore.autoMuteOnFocus else { return }
            sfxPlayer?.isMuted = isFocusActive
        }
        focusObserver.startObserving()
        focusModeObserver = focusObserver

        let body = CharacterBody(
            avatar: avatar,
            position: initialPosition,
            bounceIntensity: loadResult.manifest.bounceIntensity ?? CharacterBody.defaultBounceIntensity
        )
        characterBody = body
        let controller = CharacterController(initialState: idleState, body: body, sfxPlayer: sfxPlayer)
        for (kind, state) in [
            (StateKind.idle, idleState as StateHandler),
            (.walk, walkState), (.climb, climbState), (.walkOnTop, walkOnTopState),
            (.fall, fallState), (.land, landState), (.moveTo, moveToState),
            (.point, pointState), (.type, typeState), (.listen, listenState),
            (.reactClick, reactClickState), (.reactDrag, reactDragState),
            (.petting, pettingState), (.spin, spinState),
            (.chaseBall, chaseBallState), (.juggleBall, juggleBallState), (.kickBall, kickBallState),
            (.climbToCeiling, climbToCeilingState), (.ceiling, ceilingState),
            (.pinned, pinnedState),
        ] {
            controller.register(state, as: kind)
        }
        controller.idleChatter.keys = soundTable.keys(withPrefix: "chatter_")
        controller.roamableArea = CGRect(origin: .zero, size: groundAwareSize(of: window))
        controller.avatarHeight = avatarHitboxSize.height
        controller.walkSpeed = MovementSolver.walkSpeed * settingsStore.walkSpeedMultiplier
        // F4 reports global Quartz frames; the pet lives in overlay-local
        // pixels. Rebase once here so no state has to know both spaces.
        // Looks up the current overlay window each call rather than
        // capturing `window` -- a captured reference goes stale (weak-nils,
        // or worse, refers to a since-discarded window) the moment
        // OverlayWindowController rebuilds its windows on a real display
        // change, found via review since handleWindowsRebuilt() never
        // re-assigns this closure.
        controller.windows = { [weak self] in
            guard let self, let window = self.primaryWindow else { return [] }
            return self.overlayLocalWindows(excluding: window)
        }
        controller.landingY = { [weak self, weak controller] point in
            let floor = controller?.roamableArea.maxY ?? 0
            guard let self, let controller else { return floor }
            return LandingSurfaceResolver.landingY(
                atX: point.x,
                fallingFromY: point.y,
                windows: self.overlayLocalWindows(excluding: nil),
                screenBottomY: controller.roamableArea.maxY,
                roamableTop: controller.roamableArea.minY,
                avatarHeight: controller.avatarHeight
            )
        }
        idleState.wanderDelegate = self
        pointState.onEnter = { [weak self] in self?.beginPointingTimer() }
        characterController = controller

        // F12 (optional, lowest priority): ball-toy interaction. Lives on the
        // same sprite layer as the avatar so it reparents on display changes
        // the same way.
        makeToyBox(on: spriteView.contentLayer)

        // manifest.hitbox was decoded but had no consumer -- ClickThroughController
        // is the piece that uses it (click-through everywhere except over the
        // character), just never instantiated here. (avatarHitboxSize itself
        // is now computed earlier, above, before controller.avatarHeight needs it.)
        clickThroughController = makeClickThroughController(window: window, screenPosition: initialPosition)
    }

    /// Shared by initial setup and `handleWindowsRebuilt` -- previously
    /// duplicated verbatim at both call sites (found via review), which is
    /// exactly the kind of duplication that already caused one regression
    /// ("clicking the pet silently stops working after a display change",
    /// see the comment this used to carry at the rebuild site) since the two
    /// copies could drift.
    private func makeClickThroughController(window: NSWindow, screenPosition: CGPoint) -> ClickThroughController {
        let clickThrough = ClickThroughController(window: window)
        clickThrough.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: screenPosition, window: window),
            hitboxSize: avatarHitboxSize
        )
        clickThrough.onGesture = { [weak self] gesture in self?.handlePetGesture(gesture) }
        clickThrough.onCursorMoved = { [weak self] cursor, overHead in
            self?.handleCursorMoved(cursor, overHead: overHead)
        }
        clickThrough.onToyGesture = { [weak self] gesture in self?.handleToyGesture(gesture) }
        clickThrough.isOnPet = { [weak self] cursor in self?.isCursorOnPet(cursor) ?? false }
        clickThrough.isOnToy = { [weak self] cursor in self?.isCursorOnToy(cursor) ?? false }
        clickThrough.startMonitoring()
        return clickThrough
    }

    /// ScreenSpaceMapper's screen points are window-local (top-left origin,
    /// Y-down); NSEvent.mouseLocation (which ClickThroughController hit-tests
    /// against) is AppKit's global screen space (bottom-left origin, Y-up).
    private func globalAppKitPoint(fromWindowLocal point: CGPoint, window: NSWindow) -> CGPoint {
        CGPoint(x: window.frame.origin.x + point.x, y: window.frame.origin.y + (window.frame.height - point.y))
    }

    /// `window`'s size with the Dock's strip trimmed off the bottom (see
    /// DockInset's doc comment) -- what roamableArea/GroundedSpawnPosition
    /// should treat as "the ground," so the pet stands in front of the Dock
    /// instead of being drawn underneath it.
    private func groundAwareSize(of window: NSWindow) -> CGSize {
        let dockInset = NSScreen.screens.first
            .map { DockInset.bottomInset(screenFrame: $0.frame, visibleFrame: $0.visibleFrame) } ?? 0
        return CGSize(width: window.frame.width, height: window.frame.height - dockInset)
    }

    /// byeolki's request, 2026-07-29: "전체화면 되면 dock위가 아니라 화면
    /// 위로 다니게 바꿔줘" -- OverlayWindow already joins fullscreen Spaces
    /// (.fullScreenAuxiliary), but nothing previously re-checked
    /// groundAwareSize after initial setup, so roamableArea stayed reserved
    /// for the Dock's height even in a fullscreen Space where the Dock isn't
    /// actually shown at all (NSScreen.visibleFrame reports no Dock inset
    /// there). Space switches don't fire didChangeScreenParametersNotification
    /// (that's for real display reconfiguration), so this needs its own
    /// observer. IdleState's existing "supporting surface disappeared" check
    /// then naturally settles the pet onto the new, taller floor if the pet
    /// happens to be resting when the Space changes.
    private func setUpSpaceChangeObserving() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRoamableAreaForCurrentSpace()
        }
    }

    private func refreshRoamableAreaForCurrentSpace() {
        guard let window = primaryWindow, let controller = characterController else { return }
        controller.roamableArea = CGRect(origin: .zero, size: groundAwareSize(of: window))
    }

    /// OverlayWindowController tears down and recreates every window+SpriteLayerView
    /// on a real display change (monitor plug/unplug, resolution change).
    /// Without this, the avatar/click-through stayed parented to the now-gone
    /// window and silently disappeared. `avatar`/`clickThroughController` are
    /// nil on the very first call (fired from inside overlayController.start(),
    /// before setUpOverlayAndAvatar has built them yet) -- nothing to do then.
    private func handleWindowsRebuilt() {
        guard
            let window = primaryWindow,
            let spriteView = window.contentView as? SpriteLayerView,
            let avatar
        else {
            return
        }

        let position = GroundedSpawnPosition.position(in: groundAwareSize(of: window))
        // OverlayWindowController always orderFrontRegardless()s a freshly
        // rebuilt window -- a display change (monitor plug/unplug) shouldn't
        // silently un-hide a pet the user explicitly hid.
        if isCharacterHidden {
            window.orderOut(nil)
        }
        avatar.reparent(to: spriteView.contentLayer)
        toyBox?.reparent(to: spriteView.contentLayer)
        // Through characterBody, not avatar directly -- its didSet is the
        // only path that's supposed to push position to the avatar. Setting
        // avatar.setScreenPosition() here left characterBody.position stale,
        // desyncing the frame-loop's hitbox tracking (which reads
        // body.position) from where the pet is actually rendered, and
        // causing a visible teleport next time a movement state computed
        // from the stale position.
        characterBody?.position = position

        // Rebuilding the window drops the old monitor with its handler;
        // without re-attaching (via makeClickThroughController below),
        // clicking the pet silently stops working after a display change.
        clickThroughController?.stopMonitoring()
        clickThroughController = makeClickThroughController(window: window, screenPosition: position)
    }

    /// F4's window list rebased from global Quartz coordinates into the
    /// overlay window's local space, with our own overlay filtered out — the
    /// pet must not try to stand on the window it is drawn in.
    private func overlayLocalWindows(excluding overlay: NSWindow?) -> [WindowInfo] {
        // Reuses ScreenManager's cached GlobalScreenSpace instead of calling
        // GlobalScreenSpace.current() fresh here -- this runs every frame
        // (60Hz while active) via CharacterController.windows(), and
        // .current() re-queries NSScreen.screens and rebuilds the whole
        // space from scratch every time, for a value that only actually
        // changes on a real display reconfiguration (which ScreenManager
        // already observes and refreshes on).
        guard
            let watcher = windowListWatcher,
            let overlayFrame = primaryWindow?.frame,
            let screenSpace = screenManager?.current
        else {
            return []
        }
        // overlayFrame is AppKit space (bottom-left origin, Y-up); info.frame
        // (from CGWindowListCopyWindowInfo) is already Quartz space (primary
        // display top-left origin, Y-down) -- the same convention
        // GlobalScreenSpace normalizes into. A straight subtraction of
        // AppKit's origin with no Y-flip only happened to work for the
        // primary display's overlay window (whose AppKit origin is (0,0));
        // route through the same conversion GlobalScreenSpace itself uses for
        // every other screen frame so a non-primary overlay window works too.
        let origin = screenSpace.normalized(fromAppKit: CGPoint(x: overlayFrame.minX, y: overlayFrame.maxY))
        let overlayNumber = overlay.map { CGWindowID($0.windowNumber) }
        return watcher.windows.compactMap { info in
            guard info.windowID != overlayNumber else { return nil }
            return WindowInfo(
                windowID: info.windowID,
                ownerPID: info.ownerPID,
                ownerName: info.ownerName,
                title: info.title,
                layer: info.layer,
                frame: info.frame.offsetBy(dx: -origin.x, dy: -origin.y)
            )
        }
    }

    // MARK: - Wander (F3)

    /// IdleState computes a wander outcome and previously had nowhere to send
    /// it — `wanderDelegate` was never assigned, so the scheduler fired into
    /// the void. Picking the destination needs the roamable area (and, later,
    /// the window list), which is bootstrap knowledge, not state knowledge.
    func idleStateDidRequestWander(_ outcome: WanderScheduler.Outcome) {
        guard let controller = characterController else { return }
        switch outcome {
        case .walkToRandomPoint:
            walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
            controller.transition(to: .walk)
        case .climbNearestWindow:
            // Walk to the nearest climbable window's side; WalkState's own
            // blockingWindow check takes it from there and hands off to Climb.
            // Falls back to roaming when there's nothing to climb, rather
            // than standing still.
            walkState.target = characterBody.flatMap { body in
                WindowSupport.nearestClimbTarget(
                    from: body.position,
                    in: overlayLocalWindows(excluding: nil),
                    roamableTop: controller.roamableArea.minY,
                    avatarHeight: avatarHitboxSize.height
                )
            } ?? Self.randomRoamPoint(in: controller.roamableArea)
            controller.transition(to: .walk)
        case .climbToCeiling:
            // ClimbToCeilingState falls back to .fall on its own if there's no
            // wall underfoot, but that costs one visible frame of the climb
            // clip flashing before it drops -- byeolki: "이거 화면에 있는
            // 벽? 통해서만 올라갈 수 있게 해줘 그냥 아무 지형에서
            // 올라가버리냐". Checking here avoids ever entering the state
            // without a wall to begin with.
            guard let body = characterBody,
                  WindowSupport.windowBeingClimbed(at: body.position, in: overlayLocalWindows(excluding: nil)) != nil else {
                walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
                controller.transition(to: .walk)
                return
            }
            controller.transition(to: .climbToCeiling)
        case .playWithToy:
            // Before this draw, play could only ever start at the moment a toy
            // LANDED -- so a toy the pet had kicked away and walked off from
            // was abandoned for good. Falls back to roaming when nothing is
            // out or nothing has settled yet, same as the climbs do.
            guard !isRestingFromToys,
                  let box = toyBox,
                  let name = ToyInterestPolicy.next(
                      from: box.candidates,
                      lastPlayed: box.lastPlayedName,
                      petPosition: characterBody?.position ?? .zero
                  )
            else {
                walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
                controller.transition(to: .walk)
                return
            }
            startPlaying(with: ToyCatalogue.toy(named: name))
        case .stay:
            break
        }
    }

    /// How much of each side of the screen wander targets stay out of, as a
    /// fraction of its width. Targeting the literal edges meant a good share
    /// of wanders ended with the pet pressed into a corner, where it then sat
    /// until the next timer -- and screen-edge containment holds it there
    /// exactly, so it reads as being stuck rather than as having wandered
    /// (byeolki: "펫이 너무 구석이 박히고"). It can still be *carried* or
    /// thrown into a corner; it just won't choose one.
    static let roamEdgeMargin: CGFloat = 0.08

    private static func randomRoamPoint(in area: CGRect) -> CGPoint {
        guard area.width > 0 else { return .zero }
        let margin = area.width * roamEdgeMargin
        return CGPoint(x: CGFloat.random(in: (area.minX + margin)...(area.maxX - margin)), y: area.maxY)
    }

    // MARK: - Frame loop (F3)

    /// Nothing drove CharacterController.update(dt:) before this, so every
    /// time-based behavior was inert: IdleState's WanderScheduler never fired
    /// (the pet stood still forever) and PointingController's release timeout
    /// never elapsed. One clock ticks both.
    private func setUpFrameLoop() {
        frameClock.onTick = { [weak self] dt in
            guard let self else { return }
            self.characterController?.update(dt: dt)
            self.pointingController.tick(dt: dt)
            if let controller = self.characterController, let toyBox = self.toyBox {
                // Resolved per toy: where a toy comes to rest depends on where
                // it is and how big it is, and with several out they are in
                // different places over different windows.
                toyBox.tickAll(
                    dt: dt,
                    landingY: { ball in
                        let ballPosition = ball.state?.position ?? .zero
                        let floorLandingY = controller.landingY(ballPosition)
                        // A ball falling through the character's head bonks off
                        // it instead of passing straight through to the
                        // floor/window below -- see ToyBox.onLanded for what
                        // happens once it actually lands there.
                        let headLandingY = self.characterBody.flatMap {
                            BallHeadCollision.landingY(
                                ballX: ballPosition.x,
                                ballHalfWidth: ball.visualBounds.width / 2,
                                characterPosition: $0.position,
                                avatarSize: self.avatarHitboxSize
                            )
                        }
                        return min(floorLandingY, headLandingY ?? floorLandingY)
                    },
                    roamableArea: controller.roamableArea
                )
            }
            // Stroking ends when the cursor stops moving, which by definition
            // sends no events -- so it has to be noticed on a tick.
            self.apply(self.headPetDetector.tick(now: CACurrentMediaTime()))

            // F1's idle downshift: a resting pet doesn't need 60fps.
            let isResting = self.characterController?.currentState === self.idleState
            self.frameClock.setFramesPerSecond(self.idleFrameRate.framesPerSecond(idle: isResting, dt: dt))

            // A spin-style toy is carried above the pet's head for as long as
            // the pet is playing with it -- position and rotation both come
            // from here, since it is the frame loop that knows dt.
            if let toyBox = self.toyBox, let body = self.characterBody {
                let isPlaying = self.characterController?.currentState === self.juggleBallState
                let spins = toyBox.focusedToy?.play == .spinOverhead
                for ball in toyBox.all where ball.isActive {
                    // Only a toy the pet actually has. Held means the cursor
                    // took it; kicked means it is mid-throw, by the user or by
                    // the pet itself. Without this the pet re-attaches it to
                    // its head on the very next frame, and a spun toy can never
                    // be thrown at all (byeolki: "지팡이도 다른 장난감처럼
                    // 던져지고", 2026-07-29).
                    let petMayHold = ball.state.map { $0.phase != .held && $0.phase != .kicked } ?? false
                    if isPlaying, spins, petMayHold, ball === toyBox.focused {
                        ball.carry(
                            to: CGPoint(
                                x: body.position.x,
                                y: body.position.y - self.avatarHitboxSize.height - Self.spinHoverGap
                            ),
                            dt: dt
                        )
                    } else if ball.state?.phase == .carried {
                        // Play ended (or something interrupted it): give the
                        // toy back to physics rather than leaving it stuck in
                        // the air.
                        ball.stopCarrying()
                    }
                }
            }

            // The toy being played with can be taken away mid-game -- from the
            // menu, or by the cursor. The play states have nothing to act on
            // once it's gone, so the pet is put back to idle rather than left
            // miming a game with nothing.
            if self.isPlayingWithToy, self.toyBox?.focused == nil {
                self.characterController?.transition(to: .idle)
            }

            // The hitbox has to follow the pet, or clicks only work where it
            // first appeared.
            if let body = self.characterBody, let window = self.primaryWindow {
                self.clickThroughController?.updateCharacter(
                    screenPosition: self.globalAppKitPoint(fromWindowLocal: body.position, window: window),
                    hitboxSize: self.avatarHitboxSize,
                    isUpsideDown: body.isUpsideDown
                )
            }
        }
        frameClock.start()
    }

    /// Walks the pet over to a freshly launched app's window (M-1's visible
    /// half). The window doesn't exist the instant the app launches, so F4's
    /// list is polled briefly rather than read once.
    /// A tool was blocked by a missing permission: put the system's own
    /// request dialog on screen, and have the pet walk over and ask the user
    /// to click it (byeolki, 2026-07-31).
    ///
    /// Pointing rather than clicking is not a shortcut -- macOS will not let
    /// any app click a security dialog on the user's behalf, which
    /// plan/02_pet-app.md F10 records as the hard limit of this whole
    /// feature. Guiding *is* the interaction.
    private func guideThroughPermission(deniedFor tool: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard PermissionGuidance.shouldGuide(tool: tool, isGranted: { permission in
                switch permission {
                case .accessibility: return AccessibilityPermission.isTrusted(prompt: false)
                }
            }) != nil else {
                return
            }
            // Debounced: a run that calls find_ui_element three times would
            // otherwise stack three prompts and three bubbles.
            guard !self.isGuidingPermission else { return }
            self.isGuidingPermission = true

            let before = Set(self.overlayLocalWindows(excluding: nil).map(\.windowID))
            // macOS's own dialog, not one of ours -- it is the only thing that
            // can actually open the Accessibility pane with us pre-selected.
            _ = AccessibilityPermission.isTrusted(prompt: true)
            self.showNoticeBubble(
                Strings.text(.permissionNeededBubble, self.settingsStore.language),
                for: Self.permissionGuidanceDuration
            ) { [weak self] in
                self?.isGuidingPermission = false
            }
            self.pointAtNewWindow(excluding: before, attemptsRemaining: 12)
        }
    }

    /// True from the moment guidance starts until its bubble expires.
    private var isGuidingPermission = false

    /// Long enough to read the request and find the dialog.
    private static let permissionGuidanceDuration: TimeInterval = 6

    /// Points the pet at whichever window appeared after `known` -- the
    /// permission dialog, without having to know what macOS names it.
    ///
    /// Uses the F4 window list, which reads CGWindowList and needs no
    /// permission at all. That matters here more than anywhere else in the
    /// app: this runs precisely when the Accessibility-based lookup
    /// (find_ui_element) is the thing that just failed.
    private func pointAtNewWindow(excluding known: Set<CGWindowID>, attemptsRemaining: Int) {
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            guard let appeared = self.overlayLocalWindows(excluding: nil).first(where: { !known.contains($0.windowID) }) else {
                self.pointAtNewWindow(excluding: known, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            self.pointAt(frame: appeared.frame) {}
        }
    }

    /// The pet's "there you go" -- fired before the app opens, so the window
    /// coming up half a second later looks like the pet did it (byeolki,
    /// 2026-07-31: "약간 이 펫이 켜주는 느낌을 내고 싶은데").
    ///
    /// Point, not a bespoke state: it is the gesture the pet already uses for
    /// "look at this", and the arm is up for the whole lead-in rather than for
    /// one frame the way a jump alone would be. The jump rides on top of it
    /// for the flourish, and `app_launch` is the sound protocol section 6
    /// reserved for exactly this moment and nothing had ever played.
    private func performSummonGesture() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyEventReaction(EventReaction(
                stateTransition: .point,
                sfxKey: "app_launch",
                jump: true,
                emotion: "excited"
            ))
        }
    }

    private func sendPetToWindow(ownedBy pid: pid_t, attemptsRemaining: Int = 20) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let controller = self.characterController else { return }
            guard let window = self.overlayLocalWindows(excluding: nil).first(where: { $0.ownerPID == pid }) else {
                guard attemptsRemaining > 0 else { return } // the app never showed a window
                self.sendPetToWindow(ownedBy: pid, attemptsRemaining: attemptsRemaining - 1)
                return
            }
            self.moveToState.target = CGPoint(x: window.frame.midX, y: window.frame.minY)
            self.moveToState.nextState = .idle
            controller.transition(to: .moveTo)
        }
    }

    // MARK: - Pointing (F10/F11)

    /// point_at: walk to the target, then point at it. The tool only learns
    /// the pet arrived when Point is actually entered, which is what protocol
    /// section 4 promises the agent.
    func pointAt(frame: CGRect, onPointingStarted: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let controller = self.characterController else {
                onPointingStarted() // nothing can point; don't strand the caller
                return
            }

            // A still-pending point_at (pet hasn't arrived yet) redirects the
            // walk, same as MoveTo's target being overwritten -- but its
            // caller was still waiting on onPointingStarted, which would
            // otherwise be silently dropped and hang until ToolExecutor's
            // 15s timeout instead of getting a reply now.
            if let superseded = self.pendingPointTracker.replace(frame: frame, onStarted: onPointingStarted) {
                superseded()
            }

            // Stand beside the target rather than on top of it, so the
            // character isn't covering what it is trying to show.
            let standOffset: CGFloat = 60
            self.moveToState.target = CGPoint(x: frame.midX - standOffset, y: frame.maxY)
            self.moveToState.nextState = .point
            controller.transition(to: .moveTo)
        }
    }

    /// tool_cancel or ToolExecutor's 15s timeout for an in-flight point_at.
    /// Clears the tracked entry so a pet that arrives after cancellation
    /// doesn't still fire onPointingStarted for a call the caller was
    /// already told was cancelled (found via review).
    func cancelPointing() {
        DispatchQueue.main.async { [weak self] in
            self?.pendingPointTracker.clearPending()
        }
    }

    /// Called by PointState once the pet is in place and the point clip is up.
    private func beginPointingTimer() {
        guard let (frame, onStarted) = pendingPointTracker.consumeIfPending() else { return }

        pointingController.onPointingReleased = { [weak self] in
            self?.characterController?.transition(to: .idle)
        }
        pointingController.beginPointing(targetFrame: frame)
        onStarted()
    }

    // MARK: - Pet interaction (F1/F3)

    /// Clicking the pet makes it react; dragging carries it and dropping it
    /// lets it fall (plan/02_pet-app.md section 3). Gesture coordinates are
    /// AppKit global (bottom-left origin); the FSM works in overlay-local
    /// pixels (top-left origin), so they are converted on the way in.
    private func handlePetGesture(_ gesture: PetGesture) {
        guard let controller = characterController else { return }
        switch gesture {
        case .tapped:
            controller.transition(to: .reactClick)
        case .doubleTapped:
            // A happier, distinct reaction from a plain click -- also shows
            // the "happy" emotion if the user has mapped one in Settings,
            // same as EventRouter-driven reactions do.
            controller.transition(to: .petting)
            avatar?.showEmotion("happy")
        case .dragBegan(let point):
            // Order matters: transition(to:) calls ReactDragState.enter(),
            // which resets cursorPosition and the grab offset to nil (so a
            // stale drag can't resume mid-grab on re-entry) -- setting the
            // position before the transition let enter() immediately wipe it
            // out, and the grab offset would then be captured from wherever
            // the cursor had already moved on by, shifting the pet.
            controller.transition(to: .reactDrag)
            reactDragState.cursorPosition = windowLocalPoint(fromGlobalAppKit: point)
        case .dragMoved(let point):
            reactDragState.cursorPosition = windowLocalPoint(fromGlobalAppKit: point)
        case .dragEnded:
            reactDragState.release()
        }
    }

    /// Whether the cursor is on the pet's drawn artwork rather than on the
    /// transparent canvas around it. Converted into the pet's own space and
    /// then answered by the avatar, which is the only thing that knows how it
    /// is currently drawn (byeolki: "내가 보이는 부분만을 누를 수 있게",
    /// 2026-07-30).
    private func isCursorOnPet(_ cursor: CGPoint) -> Bool {
        guard let body = characterBody else { return false }
        let local = windowLocalPoint(fromGlobalAppKit: cursor)
        return body.hitTest(
            CGPoint(x: local.x - body.position.x, y: local.y - body.position.y),
            tolerance: Self.hitTestTolerance
        )
    }

    private func isCursorOnToy(_ cursor: CGPoint) -> Bool {
        toyUnderCursor(cursor) != nil
    }

    /// The topmost toy drawn under the cursor, or nil. Topmost rather than
    /// nearest: toys can overlap once several are out, and the one on top is
    /// the one the user sees themselves reaching for.
    private func toyUnderCursor(_ cursor: CGPoint) -> BallController? {
        toyBox?.hitTest(windowLocalPoint(fromGlobalAppKit: cursor), tolerance: Self.hitTestTolerance)
    }

    /// How far outside the artwork still counts as clicking it. Grabbing a
    /// ~130pt character by its exact silhouette is needlessly fiddly, and
    /// byeolki has reported a hitbox being hard to grab before -- but this is
    /// a fraction of the 28pt the old rectangle padded by, because it now
    /// hugs the drawing rather than a box around it.
    private static let hitTestTolerance: CGFloat = 8

    /// Picking the toy up with the cursor (byeolki: "호박도 펫처럼 커서로
    /// 집을 수 있게", 2026-07-29). The same rigid model the pet's drag uses:
    /// the grab offset is captured once so whatever point was grabbed stays
    /// under the cursor, and the toy is assigned outright rather than eased.
    private func handleToyGesture(_ gesture: PetGesture) {
        if case .dragBegan(let point) = gesture {
            // Which toy this gesture is about is decided here and held for the
            // rest of it; every other case reads `grabbedToy`.
            grabbedToy = toyUnderCursor(point)
        }
        guard let ball = grabbedToy, ball.isActive else { return }
        switch gesture {
        case .dragBegan(let point):
            // Taking the toy the pet is playing with ends the game --
            // otherwise the pet stands there playing with something it no
            // longer has, and (for a spun toy) tries to keep hold of it.
            // Picking up a DIFFERENT toy leaves the game alone.
            if ball === toyBox?.focused, isPlayingWithToy {
                ball.stopCarrying()
                toyBox?.clearFocus()
                characterController?.transition(to: .idle)
            }
            let local = windowLocalPoint(fromGlobalAppKit: point)
            toyGrabOffset = CGPoint(
                x: (ball.state?.position.x ?? local.x) - local.x,
                y: (ball.state?.position.y ?? local.y) - local.y
            )
            toyThrowVelocity.reset()
            lastToyDragTime = CACurrentMediaTime()
            ball.grab()
        case .dragMoved(let point):
            let local = windowLocalPoint(fromGlobalAppKit: point)
            let now = CACurrentMediaTime()
            toyThrowVelocity.track(to: local, dt: now - (lastToyDragTime ?? now))
            lastToyDragTime = now
            ball.move(to: CGPoint(x: local.x + toyGrabOffset.x, y: local.y + toyGrabOffset.y))
        case .dragEnded:
            // Let go of a still cursor and this is zero, i.e. the plain drop
            // it was before -- exactly like the pet's throw.
            ball.release(velocity: toyThrowVelocity.velocity)
        case .tapped, .doubleTapped:
            // A tap with no drag still counts as having picked it up and put
            // it straight back down; releasing restarts its fall.
            ball.release()
        }
    }

    /// Stroking the pet's head makes it happy, and letting go sets it
    /// twirling (byeolki: "마우스 포인터로 펫 머리 위를 쓰담 쓰담 하면 기분
    /// 좋은 표정 + 쓰담쓰담 끝나면 일정 시간동안 빙글 빙글 돌기", 2026-07-29).
    private func handleCursorMoved(_ cursor: CGPoint, overHead: Bool) {
        apply(headPetDetector.cursorMoved(to: cursor, overHead: overHead, now: CACurrentMediaTime()))
    }

    private func apply(_ update: HeadPetDetector.Update) {
        guard let controller = characterController else { return }
        switch update {
        case .began:
            // Never interrupt the pet being carried: a drag is the user's
            // hand already, and the cursor necessarily moves over the head
            // while dragging it around.
            guard controller.currentState !== reactDragState else { return }
            controller.transition(to: .petting)
            // After the transition -- enter() clears the flag.
            pettingState.beginStroking()
            avatar?.showEmotion("happy")
        case .ended:
            pettingState.endStroking()
        case .unchanged:
            break
        }
    }

    /// Inverse of globalAppKitPoint(fromWindowLocal:window:).
    private func windowLocalPoint(fromGlobalAppKit point: CGPoint) -> CGPoint {
        guard let window = primaryWindow else { return point }
        return CGPoint(x: point.x - window.frame.origin.x, y: window.frame.height - (point.y - window.frame.origin.y))
    }

    // MARK: - Window sensing (F4 level 1)

    private func setUpWindowSensing() {
        let watcher = WindowListWatcher()
        watcher.start()
        windowListWatcher = watcher
    }

    // MARK: - Tools (F11)

    private func setUpToolExecutor() {
        guard let windowListWatcher else { return }

        let executor = ToolExecutor(logger: ToolExecutionLogger())
        executor.onPermissionDenied = { [weak self] tool in self?.guideThroughPermission(deniedFor: tool) }
        let launchApp = LaunchAppHandler()
        launchApp.onLaunchRequested = { [weak self] in self?.performSummonGesture() }
        launchApp.onAppLaunched = { [weak self] pid in self?.sendPetToWindow(ownedBy: pid) }
        executor.register(launchApp)
        executor.register(ListRunningAppsHandler())
        executor.register(GetFrontmostWindowHandler(watcher: windowListWatcher))
        executor.register(RunShellHandler())
        executor.register(RunAppleScriptHandler())
        executor.register(PointAtHandler(coordinator: self))
        executor.register(ClickElementHandler())
        executor.register(FindUIElementHandler())
        toolExecutor = executor
    }

    // MARK: - Bridge (socket server, F11/F3 event routing)

    private func setUpBridgeServer() {
        guard let toolExecutor else { return }

        let router = BridgeMessageRouter(toolExecutor: toolExecutor)
        router.onEventReaction = { [weak self] reaction in self?.applyEventReaction(reaction) }
        // onClientUpdate/onChatEvent go unset here -- ShaydiAgent's own
        // ClientWindowStore consumes those now (2026-07-30), fed by its own
        // BridgeSocketClient connection, not this in-process router. This
        // router's job is back to just the pet's own reactions + relaying
        // (BridgeServer.relay handles the actual forwarding to whichever
        // gui-role connections are attached).
        bridgeMessageRouter = router

        let server = BridgeServer()
        server.onFailure = { error in
            AppLogger.shared.log(.error, "BridgeServer failed: \(error)")
        }
        server.onMalformedLine = {
            AppLogger.shared.log(.warning, "BridgeServer: dropped a malformed line from a client")
        }
        server.onGUIPresenceChanged = { [weak self] hasGUI in
            guard hasGUI else { return }
            // Fires on BridgeServer's own queue, and send() takes that queue
            // synchronously -- hop off it before sending, or it deadlocks.
            DispatchQueue.main.async {
                guard let self, let pending = self.pendingClientMirror else { return }
                self.pendingClientMirror = nil
                self.bridgeServer?.send(pending, to: .gui)
            }
        }
        server.onMessage = { message, connection in
            // Delivered on BridgeServer's background queue. The router hops to
            // main before touching anything (RealityKit, NSWorkspace,
            // WindowListWatcher) — do not add main-thread work here.
            router.handle(message) { reply in connection.send(reply) }
        }

        do {
            try server.start()
            bridgeServer = server
        } catch {
            // Independence principle: pet-app still works as a pure desktop
            // pet even if the socket can't be set up.
            AppLogger.shared.log(.error, "BridgeServer failed to start: \(error)")
        }
    }

    private func applyEventReaction(_ reaction: EventReaction) {
        if let kind = reaction.stateTransition {
            characterController?.transition(to: kind)
        }
        if let sfxKey = reaction.sfxKey {
            sfxPlayer?.trigger(sfxKey, loop: false)
        }
        if let emotion = reaction.emotion {
            avatar?.showEmotion(emotion)
        }
        if reaction.jump {
            characterBody?.triggerJump()
        }
        if let bubbleText = reaction.bubbleText {
            showAgentSummaryBubble(bubbleText)
        }
    }

    /// 02_pet-app.md F3: agent_done(ok=true) shows its summary in a "말풍선"
    /// -- reuses TextInputBubbleView's read-only notice mode (its own doc
    /// comment already anticipated this exact use, found via spec
    /// cross-check), same pattern as showWorkspaceOfflineBubble.
    private func showAgentSummaryBubble(_ summary: String) {
        // Longer than the 2.5s "workspace offline" notice -- a summary is
        // meant to actually be read, not just glanced at.
        showNoticeBubble(summary, for: 5.0)
    }

    /// The one timed-notice path (agent summary, workspace offline, mute
    /// sulk). Both handlers are reassigned on every show, not just set once:
    /// the bubble window is shared, so an input session's dismissal (which
    /// unpins the pet) would otherwise still be attached when a notice shows.
    private func showNoticeBubble(_ message: String, for duration: TimeInterval, onExpire: (() -> Void)? = nil) {
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        bubbleView.onCancel = { bubbleWindow.closeAndYieldFocus() }
        // Cleared, not reassigned: onDismiss fires from resignKey, and speech
        // never takes key in the first place. Left pointing at an input
        // session's dismissal it would also unpin the pet out from under a
        // notice.
        bubbleWindow.onDismiss = nil
        bubbleView.showMessage(message)
        // Sized and placed *after* showMessage, which is what decides the
        // typography the size is measured from.
        anchorBubbleToPet(bubbleWindow, size: TextInputBubbleView.speechSize(for: message))
        bubbleWindow.showSpeech()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak bubbleWindow] in
            bubbleWindow?.closeAndYieldFocus()
            onExpire?()
        }
    }

    /// How long the pet sulks about being muted.
    private static let mutedComplaintDuration: TimeInterval = 2

    /// byeolki (2026-07-31): muting the pet mid-session gets a sulk -- the
    /// angry face plus "제 목소리가 시끄러우신거에요?" for two seconds.
    ///
    /// It has to be a bubble rather than a line: the complaint is *about*
    /// being muted, so playing it as audio is the one thing that can't work.
    ///
    /// Only on mute going ON, and only from the Settings toggle -- Focus's
    /// auto-mute (which sets SFXPlayer directly, not the store) isn't the
    /// user telling the pet to be quiet, so it doesn't get sulked at.
    private func showMutedComplaint() {
        guard let controller = characterController else { return }

        // Front and centre, hanging in mid-air: wherever the pet happened to
        // be, it drops what it was doing and gets in the way (byeolki: "강제로
        // 펫을 화면의 중앙으로 가져와서", 2026-07-31). Pinned is what holds it
        // there -- it runs no locomotion and no gravity, so the pet stays put
        // for exactly as long as the complaint lasts.
        moveCharacter(to: CGPoint(x: controller.roamableArea.midX, y: controller.roamableArea.midY))
        // pinCharacter, not a raw .pinned transition -- it owns the
        // stateBeforePin bookkeeping, so a hotkey pin overlapping the sulk
        // can't corrupt that pairing. Transition first, then the emotion:
        // entering a state plays that state's own clip, which would otherwise
        // wipe the angry face immediately.
        pinCharacter()
        avatar?.showEmotion("angry")

        showNoticeBubble("제 목소리가 시끄러우신거에요?", for: Self.mutedComplaintDuration) { [weak self] in
            // Falling is also what puts the face back: entering Fall plays the
            // fall clip, so the sulk ends without anyone having to remember
            // which expression the pet was wearing before it. The pin
            // bookkeeping is discarded rather than restored -- resuming a
            // pre-sulk walk in mid-air would be wrong.
            self?.stateBeforePin = nil
            self?.characterController?.transition(to: .fall)
        }
    }

    // MARK: - Avatar appearance (Settings size slider, 2026-07-29)

    /// Called from AvatarManagementView when the size slider changes.
    /// `avatarHitboxSize` must be recomputed too (its click-through geometry
    /// has to track what's actually rendered), and the character's position
    /// has to be re-pushed through CharacterBody so the ground-point offset
    /// (which depends on the sprite's height) picks up the new size --
    /// otherwise the pet stays at its old screen position until the next
    /// state transition happens to move it.
    private func applyLiveAvatarScale(_ scale: Double) {
        avatar?.updateScale(scale)
        avatarHitboxSize = CGSize(width: baseHitboxSize.width * scale, height: baseHitboxSize.height * scale)
        characterController?.avatarHeight = avatarHitboxSize.height
        // Not `body.position = body.position` -- Swift rejects that as a
        // self-assignment, and CharacterBody's didSet wouldn't fire anyway.
        // Push straight to the avatar instead, at the position it already has.
        if let body = characterBody {
            avatar?.setScreenPosition(body.position)
        }
    }

    // MARK: - Global hotkeys + voice (F6/F7)

    private func setUpGlobalHotkeys() {
        let manager = GlobalHotkeyManager(bindings: settingsStore.hotkeyBindings)
        let speechService = SpeechRecognitionService(locale: Locale(identifier: settingsStore.speechRecognitionLocaleIdentifier))
        let voiceController = VoiceInputController(speechService: speechService)

        voiceController.onListenStart = { [weak self] in
            guard let self, let characterController = self.characterController else { return }
            self.stateBeforeListen = characterController.currentState
            characterController.transition(to: self.listenState)
            // F7: listen_start is an event-name sound key (plan/01_protocol.md
            // section 6), separate from the state's own "listen" clip key that
            // the shared enter() path triggers.
            self.sfxPlayer?.trigger("listen_start", loop: false)
        }
        voiceController.onListenEnd = { [weak self] in
            guard let self, let characterController = self.characterController else { return }
            characterController.transition(to: self.stateBeforeListen ?? self.idleState)
            self.stateBeforeListen = nil
        }
        voiceController.onFinalText = { [weak self] text in
            self?.sendUserInput(text: text, source: .voice)
        }
        voiceController.onError = { error in
            AppLogger.shared.log(.error, "Speech recognition error: \(error)")
        }
        voiceInputController = voiceController

        manager.onPushToTalkDown = { [weak voiceController] in voiceController?.pushToTalkDown() }
        manager.onPushToTalkUp = { [weak voiceController] in voiceController?.pushToTalkUp() }
        manager.onTextInputRequested = { [weak self] in self?.showTextInputBubble() }
        manager.onCharacterSummonRequested = { [weak self] in self?.summonCharacter() }

        if !manager.start() {
            AppLogger.shared.log(.warning, "GlobalHotkeyManager failed to start (Accessibility permission likely not granted)")
        }
        hotkeyManager = manager
    }

    /// Hands a command to whatever can act on it.
    ///
    /// F15 (2026-07-31): that now includes ShaydiAgent, because the agent
    /// moved there. Mirroring to the gui used to be the text bubble's private
    /// business -- one line in submitFromInputBubble, purely so the client
    /// window could *display* what was typed. Every input goes there now, and
    /// for the same reason a voice command previously reached nothing: the
    /// only listener it had was a workspace process that does not exist.
    private func sendUserInput(text: String, source: UserInput.Source, attachments: [Attachment] = []) {
        let message = BridgeMessage.userInput(
            UserInput(text: text, source: source, attachments: attachments.isEmpty ? nil : attachments)
        )
        let reachedClient = bridgeServer?.send(message, to: .gui) == true
        // Still offered to a workspace as well: if one ever attaches, the
        // protocol 3.3 channel is still its way in, and delivering to both is
        // harmless while only the client acts.
        let reachedWorkspace = userInputSender.send(text: text, source: source, attachments: attachments.isEmpty ? nil : attachments) == .sent

        guard !reachedClient else { return }
        // Held rather than dropped -- ShaydiAgent is launched alongside the
        // pet (CompanionAppLauncher) and is most likely still connecting.
        pendingClientMirror = message
        if !reachedWorkspace {
            // F6: tell the user why nothing happened. Re-opening the input
            // bubble here (what this used to do) just looped — typing again
            // reopened it again, and the input was never delivered.
            showWorkspaceOfflineBubble()
        }
    }

    /// byeolki (2026-07-30): "입력창에 내용을 작성하면 창이 새로 열리면서
    /// ... 입력한 내용이 보여지게". The bubble stays the lightweight capture
    /// it is; what it submits goes to workspace as usual *and* is mirrored to
    /// ShaydiAgent, which brings its window up showing the text. Closing
    /// or quitting that window changes nothing here -- it's a separate
    /// process, and the pet doesn't observe its presence.
    private func submitFromInputBubble(_ text: String, attachments: [Attachment] = []) {
        // Brought up first so the window is on its way while the text is
        // delivered; sendUserInput queues it if the connection isn't up yet.
        openClientApp()
        sendUserInput(text: text, source: .text, attachments: attachments)
    }

    /// Flushed by BridgeServer.onGUIPresenceChanged; only ever the most
    /// recent submission, since an older one being delivered late alongside
    /// it would be noise, not history.
    private var pendingClientMirror: BridgeMessage?

    /// F6 (2026-07-30 재정정): F13 클라이언트 창이 ShaydiAgent라는 별도
    /// 앱으로 분리되면서, 이 핫키는 다시 원래의 가벼운 퀵 캡처 말풍선만
    /// 담당한다 -- 무거운 전체 창을 열 이유가 없어졌음.
    private func showTextInputBubble() {
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        pinCharacter()
        // Fresh session, fresh state -- bubbleView itself is a brand-new
        // instance per makeBubble() call, but this property lives on the
        // delegate and would otherwise carry a stale attachment into a
        // session whose (also fresh) view shows no thumbnail at all.
        pendingBubbleAttachment = nil

        bubbleView.onSubmit = { [weak self] text in
            // Focus goes to ShaydiAgent below, not back to the app the
            // user invoked the bubble from -- restoring it first would flash
            // that app forward for a frame.
            bubbleWindow.closeAndYieldFocus()
            self?.unpinCharacter()
            let attachment = self?.pendingBubbleAttachment
            self?.pendingBubbleAttachment = nil
            self?.submitFromInputBubble(text, attachments: attachment.map { [$0] } ?? [])
        }
        let dismiss = { [weak self] in
            bubbleWindow.closeAndRestoreFocus()
            self?.unpinCharacter()
            self?.pendingBubbleAttachment = nil
        }
        bubbleView.onCancel = dismiss
        // Clicking away is the other way out of a Spotlight panel.
        bubbleWindow.onDismiss = dismiss
        bubbleView.onAttachRequested = { [weak self, weak bubbleView] in
            self?.startAttachmentCapture(bubbleView: bubbleView)
        }
        bubbleView.onRemoveAttachment = { [weak self, weak bubbleView] in
            self?.pendingBubbleAttachment = nil
            bubbleView?.setAttachmentThumbnail(nil)
        }
        bubbleWindow.showAndActivate()
        // After showAndActivate, not before: makeFirstResponder on a window
        // that isn't key yet doesn't put the caret in the field, so the panel
        // came up needing a click before it would take a keystroke.
        bubbleView.showInput()
    }

    /// Set once a capture completes, cleared on submit/cancel/dismiss --
    /// see showTextInputBubble(). At most one: the panel has room for a
    /// single thumbnail, and multi-image messages aren't something the
    /// quick-capture bubble needs to support.
    private var pendingBubbleAttachment: Attachment?

    /// F14 (byeolki, 2026-08-01: "마우스 드래그를 통해서 캡쳐 후
    /// attachments를 삽입할 수 있도록 해줘"). Shells out to screencapture -i
    /// rather than the bubble hiding itself first: the system's own capture
    /// overlay draws on top of everything regardless, and hiding/reshowing
    /// the panel around an async, human-paced drag risked exactly the
    /// resignKey/refocus races closeAndRestoreFocus exists to avoid
    /// elsewhere in this file.
    private func startAttachmentCapture(bubbleView: TextInputBubbleView?) {
        ScreenRegionCapture.capture { [weak self, weak bubbleView] url in
            // The interactive capture takes focus system-wide; hand it back
            // regardless of whether anything was actually captured.
            NSApp.activate(ignoringOtherApps: true)
            self?.textInputBubbleWindow?.makeKeyAndOrderFront(nil)

            guard let url else { return } // Escape, or capture failed
            self?.pendingBubbleAttachment = Attachment(path: url.path)
            bubbleView?.setAttachmentThumbnail(NSImage(contentsOf: url))
        }
    }

    /// F13 (2026-07-30): the client window is now ShaydiAgent.app, a
    /// separate Dock-resident process -- opening/focusing it is just
    /// activating that app, the same as clicking its Dock icon.
    private func openClientApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.speaki-e.ShaydiAgent") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// No-op if already pinned (repeated Option+Shift+Space while the bubble
    /// is open) -- otherwise a second call would capture .pinned itself as
    /// the state to restore to.
    private func pinCharacter() {
        guard let characterController, stateBeforePin == nil else { return }
        stateBeforePin = characterController.currentState
        characterController.transition(to: pinnedState)
    }

    private func unpinCharacter() {
        guard let characterController else { return }
        characterController.transition(to: stateBeforePin ?? idleState)
        stateBeforePin = nil
    }

    /// F6: "소켓 미연결 시 '워크스페이스 꺼져있음' 말풍선".
    private func showWorkspaceOfflineBubble() {
        showNoticeBubble("워크스페이스가 꺼져 있어요", for: 2.5)
    }

    /// Puts the bubble over the pet's head, so what it says comes from it
    /// rather than from the middle of the screen (byeolki, 2026-07-31:
    /// "말풍선이 펫한테서 나오게").
    ///
    /// Only speech does this. The Option+Shift+Space input panel stays put at
    /// its own fixed spot (bottom-center, see makeBubble) -- it's a capture
    /// field the user aims at, not something that should chase the pet
    /// around the screen.
    ///
    /// `wasMovedByUser` is deliberately ignored: a bubble the user once
    /// dragged is still the pet's speech, and leaving it parked where the pet
    /// no longer is defeats the whole point.
    private func anchorBubbleToPet(_ bubbleWindow: TextInputBubbleWindow, size: CGSize) {
        bubbleWindow.setContentSize(size)

        guard
            let window = primaryWindow,
            let screen = window.screen ?? NSScreen.main,
            let body = characterBody
        else {
            return
        }

        let petPoint = globalAppKitPoint(fromWindowLocal: body.position, window: window)
        // body.position is the pet's ground point, so its head is a hitbox up
        // from there -- in AppKit's bottom-left space, up is +y.
        let headY = petPoint.y + avatarHitboxSize.height
        var origin = CGPoint(x: petPoint.x - size.width / 2, y: headY + Self.speechBubbleGap)

        // Clamped, because a pet in a corner would otherwise put half its
        // speech off the screen. Vertically it flips below the pet instead of
        // being shoved down over its head.
        let frame = screen.visibleFrame
        origin.x = min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8)
        if origin.y + size.height > frame.maxY - 8 {
            origin.y = petPoint.y - size.height - Self.speechBubbleGap
        }
        origin.y = max(origin.y, frame.minY + 8)

        bubbleWindow.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
    }

    /// Close enough to read as attached, far enough not to cover the pet.
    private static let speechBubbleGap: CGFloat = 8
    /// Gap between the quick-capture panel and the bottom of the visible
    /// (Dock-excluded) screen area.
    private static let bottomModalMargin: CGFloat = 60

    private func makeBubble() -> (TextInputBubbleWindow, TextInputBubbleView)? {
        guard let screen = primaryWindow?.screen ?? NSScreen.main else { return nil }

        let size = TextInputBubbleView.panelSize
        let bubbleWindow = textInputBubbleWindow ?? {
            let newWindow = TextInputBubbleWindow(contentRect: CGRect(origin: .zero, size: size))
            textInputBubbleWindow = newWindow
            return newWindow
        }()

        let bubbleView = TextInputBubbleView(frame: CGRect(origin: .zero, size: size))
        bubbleWindow.setContentSize(size)
        bubbleWindow.contentView = bubbleView

        // Bottom-center (byeolki, 2026-08-01: "모달 뜨는걸 중앙 하단으로
        // 변경") -- centred across, hovering just above the Dock.
        // visibleFrame already excludes the Dock/menu bar, so this margin is
        // just breathing room, not Dock clearance.
        let frame = screen.visibleFrame
        if !bubbleWindow.wasMovedByUser {
            bubbleWindow.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + Self.bottomModalMargin
            ))
        }
        return (bubbleWindow, bubbleView)
    }

    private func summonCharacter() {
        // TODO(F3): a real "summon" (walk to the cursor/frontmost window,
        // now that MoveToState exists and is used by point_at/launch_app)
        // isn't wired up here yet. For now this just re-centers the pet on
        // the primary display, standing on the ground.
        guard let window = primaryWindow else { return }
        moveCharacter(to: GroundedSpawnPosition.position(in: groundAwareSize(of: window)))
    }

    /// Teleports the pet -- through characterBody (see handleWindowsRebuilt's
    /// comment) so the frame loop's hitbox tracking and any in-flight
    /// movement state stay consistent with where the pet actually renders.
    private func moveCharacter(to windowLocalPoint: CGPoint) {
        guard let window = primaryWindow else { return }
        characterBody?.position = windowLocalPoint
        clickThroughController?.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: windowLocalPoint, window: window),
            hitboxSize: avatarHitboxSize
        )
    }


    /// Whether the pet is currently in a toy-play state.
    private var isPlayingWithToy: Bool {
        let state = characterController?.currentState
        return state === chaseBallState || state === juggleBallState || state === kickBallState
    }

    /// Builds the toy box and wires every callback that involves a toy.
    ///
    /// Called once, at launch: individual toys come and go through the menu
    /// (ToyBox.toggle), and a display change reparents the box rather than
    /// rebuilding it.
    private func makeToyBox(on parent: CALayer) {
        let box = ToyBox(parent: parent, scale: settingsStore.toyScale)
        box.onLanded = { [weak self] toy, position in
            guard let self, let ball = self.toyBox?.controller(for: toy) else { return }
            // A toy that fell onto the character's head bonks off it
            // immediately instead of resting there to be chased (byeolki:
            // "캐릭터 머리로 떨어져서 통 튀어서"). It stays in play after the
            // bounce -- nothing removes the toy any more.
            // Compared at the toy's bottom edge, not its centre: the toy
            // rests with its artwork on the surface, so its centre sits a
            // good 20pt above whatever it landed on. Comparing centres here
            // meant a toy that had genuinely landed on the head read as
            // having missed it, and it sat on the pet instead of bouncing.
            let toyBottom = position.y + ball.visualBounds.maxY
            if let body = self.characterBody,
               let headY = BallHeadCollision.landingY(
                   ballX: position.x,
                   ballHalfWidth: ball.visualBounds.width / 2,
                   characterPosition: body.position,
                   avatarSize: self.avatarHitboxSize
               ),
               abs(toyBottom - headY) < 0.5 {
                if self.characterController?.currentState === self.juggleBallState,
                   ball === self.toyBox?.focused {
                    // Mid-game: caught, not headed. The toy is left resting on
                    // the pet's head and JuggleBall throws it again after a
                    // beat. Popping it here instead would make contact and
                    // re-launch the same instant, which reads as a bounce.
                    self.juggleBallState.caught()
                } else {
                    // Dropped on the pet's head by the user, out of the blue:
                    // it bounces off and makes its way down rather than
                    // perching there. The drift is what gets it off the head;
                    // straight up would just land on the same spot again.
                    ball.bounce(drift: .random(in: 70...110) * (Bool.random() ? 1 : -1))
                }
                return
            }

            // Idle/Walk-only gate (F3's priority rule): the pet must not
            // abandon an agent-driven task to go chase a ball. And not the
            // toy it just threw away, until it has had a break from toys --
            // otherwise the throw's own landing starts the next game.
            guard !self.isRestingFromToys,
                  let controller = self.characterController,
                  controller.currentState === self.idleState || controller.currentState === self.walkState
            else { return }
            self.startPlaying(with: toy)
        }
        juggleBallState.onThrow = { [weak self] in
            guard let self, let body = self.characterBody else { return }
            // Straight up over the pet's own x, so it comes back down on the
            // head rather than beside it.
            self.toyBox?.focused?.lift(
                overX: body.position.x,
                headTop: body.position.y - self.avatarHitboxSize.height
            )
        }
        kickBallState.onEnter = { [weak self] in
            guard let self else { return }
            // The throw-away IS the end of the game, for every toy and both
            // play styles, so this is the one place the break starts from.
            self.toyPlayEndedAt = CACurrentMediaTime()
            self.toyBox?.focused?.kick(direction: self.characterBody?.facing ?? .right)
        }
        toyBox = box
    }

    /// Sends the pet off to play with one particular toy. The single entry
    /// point into the play states, so "which toy is the pet playing with" is
    /// only ever answered in one place.
    private func startPlaying(with toy: Toy) {
        guard let controller = characterController,
              let box = toyBox,
              let ball = box.controller(for: toy),
              let position = ball.state?.position
        else { return }

        box.focus(ball)
        // Beside the toy and on the surface it's resting on -- not at the
        // toy's own centre, which is a toy-radius up in the air and puts
        // the pet on top of it.
        chaseBallState.target = ToyApproach.standingPosition(
            toyPosition: position,
            toyBounds: ball.visualBounds,
            petPosition: characterBody?.position ?? position,
            petBounds: characterBody?.visualBounds ?? .zero
        )
        juggleBallState.style = toy.play
        juggleBallState.toyName = toy.name
        controller.transition(to: .chaseBall)
    }

    // MARK: - Ball toy (F12, optional)

    /// Menu bar toy list — puts the chosen toy out at the cursor, onto
    /// whatever's below it (F4's landing-surface logic, same as Fall), or
    /// takes it away if it was already out (byeolki: "그걸 눌러서
    /// 나오게하고 다시 눌러서 없애는", 2026-07-30).
    /// Returns the toys that are out afterwards -- the settings window's toy
    /// grid seeds itself from the same answer the menu bar gets, so the two
    /// switches for one toy box can't drift apart.
    @discardableResult
    private func toggleToy(_ toy: Toy) -> Set<String> {
        guard let box = toyBox else { return [] }
        box.toggle(toy, at: windowLocalPoint(fromGlobalAppKit: NSEvent.mouseLocation))
        // Handing the pet a toy on purpose beats its break -- being ignored
        // right after clicking the menu just reads as broken.
        toyPlayEndedAt = nil
        // From what's actually out, not from what the toggle was asked to do.
        return box.outToyNames
    }
}
