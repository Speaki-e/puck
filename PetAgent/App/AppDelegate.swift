//
//  AppDelegate.swift
//  PetAgent
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
    // F3 ceiling-crawling (2026-07-29): WanderScheduler's .climbToCeiling outcome.
    private let climbToCeilingState = ClimbToCeilingState()
    private let ceilingState = CeilingState()
    // F12 (optional, lowest priority): ball-toy interaction.
    private let chaseBallState = ChaseBallState()
    private let juggleBallState = JuggleBallState()
    private let kickBallState = KickBallState()
    private var ballController: BallController?

    private let frameClock = FrameClock()
    private var idleFrameRate = IdleFrameRatePolicy()
    // Shared: PointAtHandler starts a pointing session on it, and the frame
    // clock ticks the same instance so the release timeout can elapse.
    private let pointingController = PointingController()

    private var windowListWatcher: WindowListWatcher?
    private var toolExecutor: ToolExecutor?

    private var bridgeServer: BridgeServer?
    private var bridgeMessageRouter: BridgeMessageRouter?
    private lazy var userInputSender = UserInputSender { [weak self] in self?.bridgeServer }
    /// F13 (2026-07-29): sidebar/session-list source of truth, fed by
    /// bridgeMessageRouter's onClientUpdate/onChatEvent below. The client
    /// window itself (task not yet built) will bind to this.
    private lazy var clientWindowStore = ClientWindowStore(sender: userInputSender)

    private var hotkeyManager: GlobalHotkeyManager?
    private var voiceInputController: VoiceInputController?
    private var stateBeforeListen: StateHandler?

    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?
    private var textInputBubbleWindow: TextInputBubbleWindow?
    /// F13 (2026-07-29) -- the Claude-Desktop-style client window Option+Shift+Space summons.
    private var clientWindow: ClientWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()

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
        menuBar.onOpenSettings = { [weak self] in self?.showSettingsWindow() }
        menuBar.onSwitchAvatar = { [weak self] in self?.showAvatarManagementWindow() }
        menuBar.onThrowBall = { [weak self] in self?.throwBall() }
        menuBar.onToggleVisibility = { [weak self] in self?.toggleCharacterVisibility() }
        menuBar.onQuit = { NSApplication.shared.terminate(nil) }
        menuBar.applyLanguage(settingsStore.language)
        menuBarController = menuBar
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
        menuBarController?.setVisibilityLabel(isHidden: isCharacterHidden)
    }

    /// Settings and avatar management used to be two separate windows
    /// reachable from two separate menu items -- merged into one tabbed
    /// window (byeolki's UI/UX redesign request, 2026-07-29). "Switch
    /// Avatar…" now just opens this same window on the Avatar tab instead of
    /// a second one.
    private func showSettingsWindow(initialTab: SettingsView.Tab = .general) {
        let view = SettingsView(
            store: settingsStore,
            initialTab: initialTab,
            onAvatarScaleChanged: { [weak self] scale in self?.applyLiveAvatarScale(scale) }
        )
        if let window = settingsWindow, let hosting = window.contentViewController as? NSHostingController<SettingsView> {
            // Re-set rather than just re-showing the cached window: this is
            // the only way to move an already-open window to a different
            // initial tab (e.g. Settings is open on Sound, then "Switch
            // Avatar…" is clicked).
            hosting.rootView = view
        } else {
            let hostingController = NSHostingController(rootView: view)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = Strings.text(.settingsWindowTitle, settingsStore.language)
            settingsWindow = newWindow
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAvatarManagementWindow() {
        showSettingsWindow(initialTab: .avatar)
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
            .appendingPathComponent("PetAgent/Avatars", isDirectory: true)
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

        let sfxPlayer = SFXPlayer(soundTable: SoundTable(avatarDirectory: avatarDirectory, sounds: loadResult.manifest.sounds))
        sfxPlayer.volume = settingsStore.volume
        sfxPlayer.isMuted = settingsStore.isMuted
        self.sfxPlayer = sfxPlayer

        // Previously copied once at launch only -- Settings' Volume/Mute
        // toggles had no live effect on a running session until restart.
        settingsStore.onVolumeChanged = { [weak sfxPlayer] volume in sfxPlayer?.volume = volume }
        settingsStore.onMuteChanged = { [weak sfxPlayer] isMuted in sfxPlayer?.isMuted = isMuted }
        settingsStore.onWalkSpeedMultiplierChanged = { [weak self] multiplier in
            self?.characterController?.walkSpeed = MovementSolver.walkSpeed * multiplier
        }
        // byeolki: "한국어 언어모드도 만들어주고" -- the menu bar's NSMenu
        // titles are plain strings set once at construction, unlike SwiftUI's
        // live-recomputed body, so they need an explicit push on change.
        settingsStore.onLanguageChanged = { [weak self] language in
            self?.menuBarController?.applyLanguage(language)
            self?.settingsWindow?.title = Strings.text(.settingsWindowTitle, language)
        }
        // byeolki: "화이트모드 다크모드 추가하고" -- the client window is a
        // separate SwiftUI hierarchy from Settings (where the picker lives),
        // so it needs this same explicit push to pick up a live change.
        clientWindowStore.appearance = settingsStore.appearance
        settingsStore.onAppearanceChanged = { [weak self] appearance in
            self?.clientWindowStore.appearance = appearance
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
        let ball = BallController(parent: spriteView.contentLayer)
        ball.onLanded = { [weak self] position in
            guard let self else { return }
            // A ball that fell onto the character's head bonks off
            // immediately and disappears via the existing kicked-lifetime
            // cleanup, instead of resting and waiting to be chased
            // (byeolki: "축구공을 소환하면 캐릭터 머리로 떨어져서 통
            // 튀어서 없어지게 해줘").
            if let body = self.characterBody,
               let headY = BallHeadCollision.landingY(ballX: position.x, characterPosition: body.position, avatarSize: self.avatarHitboxSize),
               abs(position.y - headY) < 0.5 {
                self.ballController?.kick(direction: Bool.random() ? .left : .right)
                return
            }

            guard let controller = self.characterController else { return }
            // Idle/Walk-only gate (F3's priority rule): the pet must not
            // abandon an agent-driven task to go chase a ball.
            guard controller.currentState === self.idleState || controller.currentState === self.walkState else { return }
            self.chaseBallState.target = position
            controller.transition(to: .chaseBall)
        }
        juggleBallState.onBounce = { [weak self] in self?.ballController?.juggle() }
        kickBallState.onEnter = { [weak self] in
            self?.ballController?.kick(direction: self?.characterBody?.facing ?? .right)
        }
        ballController = ball

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
        ballController?.reparent(to: spriteView.contentLayer)
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
            if let controller = self.characterController, let ball = self.ballController, ball.isActive {
                let ballPosition = ball.state?.position ?? .zero
                let floorLandingY = controller.landingY(ballPosition)
                // A ball falling through the character's head bonks off it
                // instead of passing straight through to the floor/window
                // below -- see BallController.onLanded for what happens once
                // it actually lands there.
                let headLandingY = self.characterBody.flatMap {
                    BallHeadCollision.landingY(ballX: ballPosition.x, characterPosition: $0.position, avatarSize: self.avatarHitboxSize)
                }
                ball.tick(
                    dt: dt,
                    landingY: min(floorLandingY, headLandingY ?? floorLandingY),
                    roamableArea: controller.roamableArea
                )
            }
            // Stroking ends when the cursor stops moving, which by definition
            // sends no events -- so it has to be noticed on a tick.
            self.apply(self.headPetDetector.tick(now: CACurrentMediaTime()))

            // F1's idle downshift: a resting pet doesn't need 60fps.
            let isResting = self.characterController?.currentState === self.idleState
            self.frameClock.setFramesPerSecond(self.idleFrameRate.framesPerSecond(idle: isResting, dt: dt))

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
        let launchApp = LaunchAppHandler()
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
        router.onClientUpdate = { [weak self] message in self?.clientWindowStore.handleClientUpdate(message) }
        router.onChatEvent = { [weak self] event, workspaceId, sessionId in
            self?.clientWindowStore.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
        }
        bridgeMessageRouter = router

        let server = BridgeServer()
        server.onFailure = { error in
            AppLogger.shared.log(.error, "BridgeServer failed: \(error)")
        }
        server.onMalformedLine = {
            AppLogger.shared.log(.warning, "BridgeServer: dropped a malformed line from a client")
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
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        bubbleView.onCancel = { bubbleWindow.closeAndRestoreFocus() }
        bubbleView.showMessage(summary)
        bubbleWindow.showAndActivate()
        // Longer than the 2.5s "workspace offline" notice -- a summary is
        // meant to actually be read, not just glanced at.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak bubbleWindow] in
            bubbleWindow?.closeAndRestoreFocus()
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
        manager.onTextInputRequested = { [weak self] in self?.showClientWindow() }
        manager.onCharacterSummonRequested = { [weak self] in self?.summonCharacter() }

        if !manager.start() {
            AppLogger.shared.log(.warning, "GlobalHotkeyManager failed to start (Accessibility permission likely not granted)")
        }
        hotkeyManager = manager
    }

    private func sendUserInput(text: String, source: UserInput.Source) {
        // Routed through clientWindowStore (2026-07-29) rather than
        // userInputSender directly, so it already targets whichever
        // workspace/session is active once the real client window (F13,
        // not yet built) lets the user switch away from the default.
        switch clientWindowStore.sendMessage(text, source: source) {
        case .sent:
            break
        case .workspaceDisconnected:
            // F6: tell the user why nothing happened. Re-opening the input
            // bubble here (what this used to do) just looped — typing again
            // reopened it again, and the input was never delivered.
            showWorkspaceOfflineBubble()
        }
    }

    /// F13 (2026-07-29): Option+Shift+Space pins the character and summons
    /// the client window (byeolki: "캐릭터를 고정하고 그 옆에 입력 모달을
    /// 보이고") -- docked beside it on first open, refocused if already open.
    private func showClientWindow() {
        pinCharacter()

        let window = clientWindow ?? {
            let newWindow = ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 480))
            newWindow.onWillClose = { [weak self] in self?.unpinCharacter() }
            let hostingController = NSHostingController(rootView: ClientWindowView(store: clientWindowStore))
            newWindow.contentViewController = hostingController
            clientWindow = newWindow
            return newWindow
        }()

        if let primaryWindow {
            let center = CGPoint(x: primaryWindow.frame.midX, y: primaryWindow.frame.midY)
            window.setFrameOrigin(NSPoint(x: center.x + 80, y: center.y))
        }
        window.showAndActivate()
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
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        bubbleView.onCancel = { bubbleWindow.closeAndRestoreFocus() }
        bubbleView.showMessage("워크스페이스가 꺼져 있어요")
        bubbleWindow.showAndActivate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak bubbleWindow] in
            bubbleWindow?.closeAndRestoreFocus()
        }
    }

    private func makeBubble() -> (TextInputBubbleWindow, TextInputBubbleView)? {
        guard let window = primaryWindow else { return nil }

        let bubbleWindow = textInputBubbleWindow ?? {
            let newWindow = TextInputBubbleWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 40))
            textInputBubbleWindow = newWindow
            return newWindow
        }()

        let bubbleView = TextInputBubbleView(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        bubbleWindow.contentView = bubbleView

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        bubbleWindow.setFrameOrigin(NSPoint(x: center.x - 120, y: center.y))
        return (bubbleWindow, bubbleView)
    }

    private func summonCharacter() {
        // TODO(F3): a real "summon" (walk to the cursor/frontmost window,
        // now that MoveToState exists and is used by point_at/launch_app)
        // isn't wired up here yet. For now this just re-centers the pet on
        // the primary display, standing on the ground.
        guard let window = primaryWindow else { return }
        let position = GroundedSpawnPosition.position(in: groundAwareSize(of: window))
        // Through characterBody (see handleWindowsRebuilt's comment) so the
        // frame-loop's hitbox tracking and any in-flight movement state stay
        // consistent with where the pet actually renders.
        characterBody?.position = position
        clickThroughController?.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: position, window: window),
            hitboxSize: avatarHitboxSize
        )
    }

    // MARK: - Ball toy (F12, optional)

    /// Menu bar "Throw Ball" — spawns one ball at the cursor, which drops
    /// straight down onto whatever's below it (F4's landing-surface logic,
    /// same as Fall). One at a time: a second throw while one is still in
    /// play is a no-op rather than piling up balls.
    private func throwBall() {
        guard let ball = ballController, !ball.isActive else { return }
        let spawnPoint = windowLocalPoint(fromGlobalAppKit: NSEvent.mouseLocation)
        ball.spawn(at: spawnPoint)
    }
}
