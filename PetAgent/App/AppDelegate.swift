//
//  AppDelegate.swift
//  PetAgent
//
//  Shared · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  Coordinates the init order: permission self-check -> overlay -> bridge
//  server -> global hotkeys.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // TODO: initialize in order: PermissionOnboarding -> OverlayWindowController ->
        // BridgeServer -> GlobalHotkeyManager. Wire each one in as it gets implemented.
    }
}
