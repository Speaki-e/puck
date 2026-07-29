//
//  PetAgentClientApp.swift
//  PetAgentClient
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  @main entry point -- a regular (Dock-resident) app, unlike PetAgent's
//  LSUIElement menu-bar lifecycle. This app *is* the Claude-Desktop-style
//  client window; PetAgent stays a pure pet + bridge.sock host (2026-07-30).
//

import AppKit

@main
enum PetAgentClientApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
