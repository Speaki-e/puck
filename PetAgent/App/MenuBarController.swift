//
//  MenuBarController.swift
//  PetAgent
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  NSStatusItem menu: open settings, switch avatar, quit
//

import AppKit

final class MenuBarController {
    var onOpenSettings: (() -> Void)?
    var onSwitchAvatar: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PetAgent")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Switch Avatar…", action: #selector(handleSwitchAvatar), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PetAgent", action: #selector(handleQuit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func handleOpenSettings() { onOpenSettings?() }
    @objc private func handleSwitchAvatar() { onSwitchAvatar?() }
    @objc private func handleQuit() { onQuit?() }
}
