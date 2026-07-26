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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()

    private var screenManager: ScreenManager?
    private var overlayController: OverlayWindowController?
    private var characterController: CharacterController?
    private var avatar: USDZAvatar?
    private var sfxPlayer: SFXPlayer?

    private var windowListWatcher: WindowListWatcher?
    private var toolExecutor: ToolExecutor?

    private var bridgeServer: BridgeServer?
    private var activeConnection: BridgeConnection?

    private var hotkeyManager: GlobalHotkeyManager?
    private var voiceInputController: VoiceInputController?
    private var stateBeforeListen: StateHandler?

    private var menuBarController: MenuBarController?
    private var settingsWindow: NSWindow?
    private var avatarManagementWindow: NSWindow?
    private var textInputBubbleWindow: TextInputBubbleWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let permissionStatus = PermissionOnboarding.currentStatus()
        AppLogger.shared.log(.info, "Launch permission status: \(permissionStatus)")

        setUpMenuBar()
        setUpOverlayAndAvatar()
        setUpWindowSensing()
        setUpToolExecutor()
        setUpBridgeServer()
        setUpGlobalHotkeys()
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
        overlayController.start()
        self.overlayController = overlayController

        guard
            let window = overlayController.windows.first,
            let arView = window.contentView as? PetARView
        else {
            return
        }

        let avatarDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PetAgent/Avatars/dummy")
        guard let loadResult = try? AvatarLoader.load(avatarDirectory: avatarDirectory) else {
            AppLogger.shared.log(.error, "Failed to load dummy avatar at \(avatarDirectory.path)")
            return
        }

        let mapper = ScreenSpaceMapper(viewportSize: window.frame.size)
        let avatar = USDZAvatar(
            avatarDirectory: avatarDirectory,
            loadResult: loadResult,
            parent: arView.contentAnchor,
            screenSpaceMapper: mapper
        )
        avatar.setScreenPosition(CGPoint(x: window.frame.width / 2, y: window.frame.height / 2))
        self.avatar = avatar

        let sfxPlayer = SFXPlayer(soundTable: SoundTable(avatarDirectory: avatarDirectory, sounds: loadResult.manifest.sounds))
        sfxPlayer.volume = settingsStore.volume
        sfxPlayer.isMuted = settingsStore.isMuted
        self.sfxPlayer = sfxPlayer

        characterController = CharacterController(initialState: IdleState(), avatar: avatar, sfxPlayer: sfxPlayer)
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
        executor.register(LaunchAppHandler())
        executor.register(ListRunningAppsHandler())
        executor.register(GetFrontmostWindowHandler(watcher: windowListWatcher))
        executor.register(RunShellHandler())
        executor.register(RunAppleScriptHandler())
        executor.register(PointAtHandler(pointingController: PointingController()))
        executor.register(ClickElementHandler())
        // FindUIElementHandler still needs F4 level 2 (UIElementInspector) — not registered yet.
        toolExecutor = executor
    }

    // MARK: - Bridge (socket server, F11/F3 event routing)

    private func setUpBridgeServer() {
        guard let toolExecutor else { return }

        let server = BridgeServer()
        server.onFailure = { error in
            AppLogger.shared.log(.error, "BridgeServer failed: \(error)")
        }
        server.onMessage = { [weak self] message, connection in
            self?.activeConnection = connection
            self?.handleBridgeMessage(message, connection: connection, toolExecutor: toolExecutor)
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

    private func handleBridgeMessage(_ message: BridgeMessage, connection: BridgeConnection, toolExecutor: ToolExecutor) {
        switch message {
        case .toolDispatch(let dispatch):
            toolExecutor.dispatch(dispatch) { result in
                connection.send(.toolResult(result))
            }
        case .event(let event):
            applyEventReaction(EventRouter.reaction(for: event))
        case .toolResult, .userInput:
            break // pet-app only ever sends these, never receives them
        }
    }

    private func applyEventReaction(_ reaction: EventReaction) {
        // NOTE: creates a fresh state instance per reaction rather than
        // reusing shared singletons, so CharacterController's same-state
        // no-op guard (reference equality) won't catch re-entering the same
        // logical state twice in a row. Sharing one instance per state is a
        // reasonable follow-up polish item, not required for this to work.
        if let kind = reaction.stateTransition, let characterController {
            let state: StateHandler
            switch kind {
            case .idle: state = IdleState()
            case .type: state = TypeState()
            case .point: state = PointState()
            case .reactClick: state = ReactClickState()
            }
            characterController.transition(to: state)
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
            characterController.transition(to: ListenState())
        }
        voiceController.onListenEnd = { [weak self] in
            guard let self, let characterController = self.characterController else { return }
            characterController.transition(to: self.stateBeforeListen ?? IdleState())
            self.stateBeforeListen = nil
        }
        voiceController.onFinalText = { [weak self] text in
            self?.sendUserInput(text: text, source: .voice)
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
        guard let activeConnection else {
            // protocol section 2: pet-app has no way to send when nothing is
            // connected; surface that instead of silently dropping the input.
            showTextInputBubble()
            return
        }
        activeConnection.send(.userInput(UserInput(text: text, source: source)))
    }

    private func showTextInputBubble() {
        guard let window = overlayController?.windows.first else { return }

        let bubbleWindow = textInputBubbleWindow ?? {
            let newWindow = TextInputBubbleWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 40))
            textInputBubbleWindow = newWindow
            return newWindow
        }()

        let bubbleView = TextInputBubbleView(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        bubbleView.onSubmit = { [weak self] text in
            self?.sendUserInput(text: text, source: .text)
            bubbleWindow.closeAndRestoreFocus()
        }
        bubbleView.onCancel = {
            bubbleWindow.closeAndRestoreFocus()
        }
        bubbleWindow.contentView = bubbleView

        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        bubbleWindow.setFrameOrigin(NSPoint(x: center.x - 120, y: center.y))
        bubbleWindow.showAndActivate()
    }

    private func summonCharacter() {
        // TODO(F3): a real "summon" (walk to the cursor/frontmost window)
        // needs MoveTo's real movement math, which isn't implemented yet.
        // For now this just re-centers the avatar on the primary display.
        guard let window = overlayController?.windows.first else { return }
        avatar?.setScreenPosition(CGPoint(x: window.frame.width / 2, y: window.frame.height / 2))
    }
}
