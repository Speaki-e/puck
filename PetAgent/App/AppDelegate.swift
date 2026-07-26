//
//  AppDelegate.swift
//  PetAgent
//
//  Shared · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Coordinates the init order: permission self-check -> overlay -> bridge
//  server -> global hotkeys.
//

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    // TODO: PermissionOnboarding, BridgeServer, GlobalHotkeyManager still need
    // wiring in here (Task 13). What's below is enough to show a static/idle
    // avatar on screen with no permissions required — overlay rendering
    // itself doesn't need Accessibility/mic/etc.
    private var screenManager: ScreenManager?
    private var overlayController: OverlayWindowController?
    private var characterController: CharacterController?
    private var avatar: USDZAvatar?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        characterController = CharacterController(initialState: IdleState(), avatar: avatar, sfxPlayer: sfxPlayer)
    }
}
