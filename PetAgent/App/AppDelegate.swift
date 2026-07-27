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
    private var avatar: USDZAvatar?
    private var sfxPlayer: SFXPlayer?
    private var clickThroughController: ClickThroughController?
    private var avatarHitboxSize: CGSize = .zero
    private var characterBody: CharacterBody?
    private var pendingPointFrame: CGRect?
    private var pendingPointStarted: (() -> Void)?
    private var focusModeObserver: FocusModeObserver?

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

    private var hotkeyManager: GlobalHotkeyManager?
    private var voiceInputController: VoiceInputController?
    private var stateBeforeListen: StateHandler?

    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?
    private var avatarManagementWindow: NSWindow?
    private var textInputBubbleWindow: TextInputBubbleWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestPermissions()

        setUpMenuBar()
        setUpOverlayAndAvatar()
        setUpWindowSensing()
        setUpToolExecutor()
        setUpBridgeServer()
        setUpGlobalHotkeys()
        setUpFrameLoop()
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
        menuBar.onQuit = { NSApplication.shared.terminate(nil) }
        menuBarController = menuBar
    }

    private func showSettingsWindow() {
        let window = settingsWindow ?? {
            let hostingController = NSHostingController(rootView: SettingsView(store: settingsStore))
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "PetAgent Settings"
            settingsWindow = newWindow
            return newWindow
        }()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAvatarManagementWindow() {
        let window = avatarManagementWindow ?? {
            let hostingController = NSHostingController(rootView: AvatarManagementView())
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Switch Avatar"
            avatarManagementWindow = newWindow
            return newWindow
        }()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            let arView = window.contentView as? PetARView
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

        let mapper = ScreenSpaceMapper(viewportSize: window.frame.size)
        let avatar = USDZAvatar(
            avatarDirectory: avatarDirectory,
            loadResult: loadResult,
            parent: arView.contentAnchor,
            screenSpaceMapper: mapper
        )
        let initialPosition = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
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

        // autoMuteOnFocus existed as a setting with nothing acting on it --
        // FocusModeObserver was implemented but never instantiated anywhere.
        let focusObserver = FocusModeObserver()
        focusObserver.onChange = { [weak self, weak sfxPlayer] isFocusActive in
            guard let self, self.settingsStore.autoMuteOnFocus else { return }
            sfxPlayer?.isMuted = isFocusActive
        }
        focusObserver.startObserving()
        focusModeObserver = focusObserver

        let body = CharacterBody(avatar: avatar, position: initialPosition)
        characterBody = body
        let controller = CharacterController(initialState: idleState, body: body, sfxPlayer: sfxPlayer)
        for (kind, state) in [
            (StateKind.idle, idleState as StateHandler),
            (.walk, walkState), (.climb, climbState), (.walkOnTop, walkOnTopState),
            (.fall, fallState), (.land, landState), (.moveTo, moveToState),
            (.point, pointState), (.type, typeState), (.listen, listenState),
            (.reactClick, reactClickState), (.reactDrag, reactDragState),
        ] {
            controller.register(state, as: kind)
        }
        controller.roamableArea = CGRect(origin: .zero, size: window.frame.size)
        // F4 reports global Quartz frames; the pet lives in overlay-local
        // pixels. Rebase once here so no state has to know both spaces.
        controller.windows = { [weak self, weak window] in
            guard let self, let window else { return [] }
            return self.overlayLocalWindows(excluding: window)
        }
        controller.landingY = { [weak self, weak controller] point in
            let floor = controller?.roamableArea.maxY ?? 0
            guard let self, let controller else { return floor }
            return LandingSurfaceResolver.landingY(
                atX: point.x,
                fallingFromY: point.y,
                windows: self.overlayLocalWindows(excluding: nil),
                screenBottomY: controller.roamableArea.maxY
            )
        }
        idleState.wanderDelegate = self
        pointState.onEnter = { [weak self] in self?.beginPointingTimer() }
        characterController = controller

        // manifest.hitbox was decoded but had no consumer -- ClickThroughController
        // is the piece that uses it (click-through everywhere except over the
        // character), just never instantiated here.
        avatarHitboxSize = CGSize(width: loadResult.manifest.hitbox.width, height: loadResult.manifest.hitbox.height)
        let clickThrough = ClickThroughController(window: window)
        clickThrough.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: initialPosition, window: window),
            hitboxSize: avatarHitboxSize
        )
        clickThrough.onGesture = { [weak self] gesture in self?.handlePetGesture(gesture) }
        clickThrough.startMonitoring()
        clickThroughController = clickThrough
    }

    /// ScreenSpaceMapper's screen points are window-local (top-left origin,
    /// Y-down); NSEvent.mouseLocation (which ClickThroughController hit-tests
    /// against) is AppKit's global screen space (bottom-left origin, Y-up).
    private func globalAppKitPoint(fromWindowLocal point: CGPoint, window: NSWindow) -> CGPoint {
        CGPoint(x: window.frame.origin.x + point.x, y: window.frame.origin.y + (window.frame.height - point.y))
    }

    /// OverlayWindowController tears down and recreates every window+PetARView
    /// on a real display change (monitor plug/unplug, resolution change).
    /// Without this, the avatar/click-through stayed parented to the now-gone
    /// window and silently disappeared. `avatar`/`clickThroughController` are
    /// nil on the very first call (fired from inside overlayController.start(),
    /// before setUpOverlayAndAvatar has built them yet) -- nothing to do then.
    private func handleWindowsRebuilt() {
        guard
            let window = overlayController?.windows.first,
            let arView = window.contentView as? PetARView,
            let avatar
        else {
            return
        }

        let position = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        avatar.reparent(to: arView.contentAnchor, screenSpaceMapper: ScreenSpaceMapper(viewportSize: window.frame.size))
        avatar.setScreenPosition(position)

        clickThroughController?.stopMonitoring()
        let clickThrough = ClickThroughController(window: window)
        clickThrough.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: position, window: window),
            hitboxSize: avatarHitboxSize
        )
        // Rebuilding the window drops the old monitor with its handler; without
        // re-attaching, clicking the pet silently stops working after a display
        // change.
        clickThrough.onGesture = { [weak self] gesture in self?.handlePetGesture(gesture) }
        clickThrough.startMonitoring()
        clickThroughController = clickThrough
    }

    /// F4's window list rebased from global Quartz coordinates into the
    /// overlay window's local space, with our own overlay filtered out — the
    /// pet must not try to stand on the window it is drawn in.
    private func overlayLocalWindows(excluding overlay: NSWindow?) -> [WindowInfo] {
        guard let watcher = windowListWatcher, let origin = overlayController?.windows.first?.frame.origin else {
            return []
        }
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
            // Needs F4's window list to choose a window; until Climb is wired
            // to it, roam instead of standing still.
            walkState.target = Self.randomRoamPoint(in: controller.roamableArea)
            controller.transition(to: .walk)
        case .stay:
            break
        }
    }

    private static func randomRoamPoint(in area: CGRect) -> CGPoint {
        guard area.width > 0 else { return .zero }
        return CGPoint(x: CGFloat.random(in: area.minX...area.maxX), y: area.maxY)
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
            // F1's idle downshift: a resting pet doesn't need 60fps.
            let isResting = self.characterController?.currentState === self.idleState
            self.frameClock.setFramesPerSecond(self.idleFrameRate.framesPerSecond(idle: isResting, dt: dt))

            // The hitbox has to follow the pet, or clicks only work where it
            // first appeared.
            if let body = self.characterBody, let window = self.overlayController?.windows.first {
                self.clickThroughController?.updateCharacter(
                    screenPosition: self.globalAppKitPoint(fromWindowLocal: body.position, window: window),
                    hitboxSize: self.avatarHitboxSize
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

            // Stand beside the target rather than on top of it, so the
            // character isn't covering what it is trying to show.
            let standOffset: CGFloat = 60
            self.moveToState.target = CGPoint(x: frame.midX - standOffset, y: frame.maxY)
            self.moveToState.nextState = .point

            self.pendingPointFrame = frame
            self.pendingPointStarted = onPointingStarted
            controller.transition(to: .moveTo)
        }
    }

    /// Called by PointState once the pet is in place and the point clip is up.
    private func beginPointingTimer() {
        guard let frame = pendingPointFrame else { return }
        pendingPointFrame = nil

        pointingController.onPointingReleased = { [weak self] in
            self?.characterController?.transition(to: .idle)
        }
        pointingController.beginPointing(targetFrame: frame)
        pendingPointStarted?()
        pendingPointStarted = nil
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
        case .dragBegan(let point):
            reactDragState.cursorPosition = windowLocalPoint(fromGlobalAppKit: point)
            controller.transition(to: .reactDrag)
        case .dragMoved(let point):
            reactDragState.cursorPosition = windowLocalPoint(fromGlobalAppKit: point)
        case .dragEnded:
            reactDragState.release()
        }
    }

    /// Inverse of globalAppKitPoint(fromWindowLocal:window:).
    private func windowLocalPoint(fromGlobalAppKit point: CGPoint) -> CGPoint {
        guard let window = overlayController?.windows.first else { return point }
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
        bridgeMessageRouter = router

        let server = BridgeServer()
        server.onFailure = { error in
            AppLogger.shared.log(.error, "BridgeServer failed: \(error)")
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
        // TODO: reaction.jump (Overlay hop animation) and reaction.bubbleText
        // (F6 text bubble, read-only display mode) aren't wired up yet.
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

    private func sendUserInput(text: String, source: UserInput.Source) {
        switch userInputSender.send(text: text, source: source) {
        case .sent:
            break
        case .workspaceDisconnected:
            // F6: tell the user why nothing happened. Re-opening the input
            // bubble here (what this used to do) just looped — typing again
            // reopened it again, and the input was never delivered.
            showWorkspaceOfflineBubble()
        }
    }

    private func showTextInputBubble() {
        guard let (bubbleWindow, bubbleView) = makeBubble() else { return }

        bubbleView.onSubmit = { [weak self] text in
            bubbleWindow.closeAndRestoreFocus()
            self?.sendUserInput(text: text, source: .text)
        }
        bubbleView.onCancel = { bubbleWindow.closeAndRestoreFocus() }
        bubbleView.showInput()
        bubbleWindow.showAndActivate()
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
        guard let window = overlayController?.windows.first else { return nil }

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
        // TODO(F3): a real "summon" (walk to the cursor/frontmost window)
        // needs MoveTo's real movement math, which isn't implemented yet.
        // For now this just re-centers the avatar on the primary display.
        guard let window = overlayController?.windows.first else { return }
        let position = CGPoint(x: window.frame.width / 2, y: window.frame.height / 2)
        avatar?.setScreenPosition(position)
        clickThroughController?.updateCharacter(
            screenPosition: globalAppKitPoint(fromWindowLocal: position, window: window),
            hitboxSize: avatarHitboxSize
        )
    }
}
