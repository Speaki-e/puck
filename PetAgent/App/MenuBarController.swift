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
    private let settingsItem: NSMenuItem
    private let switchAvatarItem: NSMenuItem
    private let throwBallItem: NSMenuItem
    private let visibilityMenuItem: NSMenuItem
    private let quitItem: NSMenuItem
    /// setVisibilityLabel's callers don't know the current language --
    /// remembered here so toggling visibility keeps using whichever
    /// language applyLanguage last set (byeolki: "한국어 언어모드도
    /// 만들어주고").
    private var language: AppLanguage = .english
    private var isCharacterHidden = false

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PetAgent")

        settingsItem = NSMenuItem(title: "", action: #selector(handleOpenSettings), keyEquivalent: ",")
        switchAvatarItem = NSMenuItem(title: "", action: #selector(handleSwitchAvatar), keyEquivalent: "")
        throwBallItem = NSMenuItem(title: "", action: #selector(handleThrowBall), keyEquivalent: "")
        visibilityMenuItem = NSMenuItem(title: "", action: #selector(handleToggleVisibility), keyEquivalent: "h")
        quitItem = NSMenuItem(title: "", action: #selector(handleQuit), keyEquivalent: "q")

        for item in [settingsItem, switchAvatarItem, throwBallItem, visibilityMenuItem, quitItem] {
            item.target = self
        }

        let menu = NSMenu()
        menu.addItem(settingsItem)
        menu.addItem(switchAvatarItem)
        menu.addItem(throwBallItem)
        menu.addItem(visibilityMenuItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        applyLanguage(.english)
    }

    /// byeolki: "한국어 언어모드도 만들어주고" -- unlike SwiftUI's
    /// live-recomputed body, these are plain NSMenuItem titles set once at
    /// construction, so Settings' language picker needs to push updates here
    /// explicitly.
    func applyLanguage(_ language: AppLanguage) {
        self.language = language
        settingsItem.title = Strings.text(.menuSettings, language)
        switchAvatarItem.title = Strings.text(.menuSwitchAvatar, language)
        throwBallItem.title = Strings.text(.menuThrowBall, language)
        quitItem.title = Strings.text(.menuQuit, language)
        setVisibilityLabel(isHidden: isCharacterHidden)
    }

    /// AppDelegate calls this after actually toggling visibility, so the
    /// menu item's label always reflects real state instead of assuming its
    /// own toggle succeeded.
    func setVisibilityLabel(isHidden: Bool) {
        isCharacterHidden = isHidden
        visibilityMenuItem.title = Strings.text(isHidden ? .menuShow : .menuHide, language)
    }

    @objc private func handleOpenSettings() { onOpenSettings?() }
    @objc private func handleSwitchAvatar() { onSwitchAvatar?() }
    @objc private func handleThrowBall() { onThrowBall?() }
    @objc private func handleToggleVisibility() { onToggleVisibility?() }
    @objc private func handleQuit() { onQuit?() }
}
