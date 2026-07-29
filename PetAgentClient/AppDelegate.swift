//
//  AppDelegate.swift
//  PetAgentClient
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  The Claude-Desktop-style client window used to live in-process inside
//  PetAgent; it moved here (2026-07-30) so it can be a regular, Dock-
//  resident app rather than sharing PetAgent's LSUIElement lifecycle
//  (byeolki: "별도의 앱으로 해서 dock에 상시 표시"). PetAgent still hosts
//  bridge.sock -- this app is just another client of it, identifying
//  itself with client_hello role "gui" (protocol 3.7).
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bridgeClient = BridgeSocketClient()
    private lazy var userInputSender = UserInputSender(transport: { [weak self] in self?.bridgeClient })
    private lazy var clientWindowStore = ClientWindowStore(sender: userInputSender)
    private var window: ClientWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // byeolki: "둘이 같이 가야하는거임" -- launching either app brings up
        // the other, since this app is useless without PetAgent hosting
        // bridge.sock on the other end.
        CompanionAppLauncher.launchIfNeeded(bundleIdentifier: "com.speaki-e.PetAgent")

        bridgeClient.onMessage = { [weak self] message in
            DispatchQueue.main.async { self?.handle(message) }
        }
        bridgeClient.start()

        showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    /// A regular Dock-resident app stays running with its Dock icon after
    /// its one window closes (like Mail, Notes, ...) -- closing the window
    /// is not the same as quitting.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func handle(_ message: BridgeMessage) {
        switch message {
        case .event(let event, let workspaceId, let sessionId):
            clientWindowStore.handleChatEvent(event, workspaceId: workspaceId, sessionId: sessionId)
        case .workspaceCreate, .sessionCreate, .editorViewReady, .editorViewUnavailable:
            clientWindowStore.handleClientUpdate(message)
        default:
            break // relayed to this connection only ever as one of the above (protocol 3.7)
        }
    }

    private func showWindow() {
        let window = window ?? {
            let newWindow = ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 480))
            newWindow.contentViewController = NSHostingController(rootView: ClientWindowView(store: clientWindowStore))
            self.window = newWindow
            return newWindow
        }()
        window.showAndActivate()
    }
}
