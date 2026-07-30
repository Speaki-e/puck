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
        case .userInput(let input):
            // Mirrored from pet-app's quick-capture bubble: typing there has
            // to bring this window up with the text already in the chat
            // (byeolki, 2026-07-30). Only shows the window if the message
            // actually landed in a session -- an unknown workspace/session
            // would pop an empty window for nothing.
            if clientWindowStore.showUserMessage(input.text, workspaceId: input.workspaceId, sessionId: input.sessionId) {
                showWindow()
            }
        default:
            break // relayed to this connection only ever as one of the above (protocol 3.7)
        }
    }

    private func showWindow() {
        let window = window ?? {
            // 720x480 was cramped for a sidebar + transcript + editor pane
            // (byeolki: "기본으로 보여지는 창의 크기를 좀 키워줘"), and at
            // origin (0,0) it opened in the bottom-left corner.
            let newWindow = ClientWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 740))
            let hosting = NSHostingController(rootView: ClientWindowView(store: clientWindowStore))
            // NSHostingController defaults to sizingOptions
            // .preferredContentSize, i.e. it keeps pushing the SwiftUI
            // fitting size onto the window -- which is why the window opened
            // at whatever the layout happened to fit in (~884x651, then
            // 700x471) no matter what contentRect or setContentSize said.
            hosting.sizingOptions = []
            newWindow.contentViewController = hosting
            newWindow.setContentSize(CGSize(width: 1100, height: 740))
            newWindow.minSize = CGSize(width: 760, height: 520)
            newWindow.center()
            self.window = newWindow
            return newWindow
        }()
        window.showAndActivate()
    }
}
