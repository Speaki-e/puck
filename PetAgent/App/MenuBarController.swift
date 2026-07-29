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
    /// F12 (optional): spawns a ball the pet chases and kicks away. Lowest
    /// priority, purely decorative -- see 02_pet-app.md F12.
    var onThrowBall: (() -> Void)?
    /// byeolki's request, 2026-07-29: hide/show the pet without quitting.
    var onToggleVisibility: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let visibilityMenuItem: NSMenuItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PetAgent")

        visibilityMenuItem = NSMenuItem(title: "Hide", action: #selector(handleToggleVisibility), keyEquivalent: "h")

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(handleOpenSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Switch Avatar…", action: #selector(handleSwitchAvatar), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Throw Ball", action: #selector(handleThrowBall), keyEquivalent: "").target = self
        visibilityMenuItem.target = self
        menu.addItem(visibilityMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PetAgent", action: #selector(handleQuit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    /// AppDelegate calls this after actually toggling visibility, so the
    /// menu item's label always reflects real state instead of assuming its
    /// own toggle succeeded.
    func setVisibilityLabel(isHidden: Bool) {
        visibilityMenuItem.title = isHidden ? "Show" : "Hide"
    }

    @objc private func handleOpenSettings() { onOpenSettings?() }
    @objc private func handleSwitchAvatar() { onSwitchAvatar?() }
    @objc private func handleThrowBall() { onThrowBall?() }
    @objc private func handleToggleVisibility() { onToggleVisibility?() }
    @objc private func handleQuit() { onQuit?() }
}
