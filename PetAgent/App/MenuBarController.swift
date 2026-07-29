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
    /// Which toy to fetch. The menu is where the toy is summoned from, so it
    /// is also where it gets picked -- Settings keeps the same choice, but
    /// having to go there first to change what "throw" throws is a step
    /// nobody expects (byeolki: "메뉴에서 지팡이 추가가 없는데", 2026-07-29).
    var onThrowToy: ((Toy) -> Void)?
    /// byeolki's request, 2026-07-29: hide/show the pet without quitting.
    var onToggleVisibility: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let settingsItem: NSMenuItem
    private let switchAvatarItem: NSMenuItem
    /// One entry per toy in the catalogue, built once -- adding a toy to
    /// ToyCatalogue puts it in this menu with no further wiring.
    private let throwToyItem: NSMenuItem
    private let throwToyMenu = NSMenu()
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
        throwToyItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        visibilityMenuItem = NSMenuItem(title: "", action: #selector(handleToggleVisibility), keyEquivalent: "h")
        quitItem = NSMenuItem(title: "", action: #selector(handleQuit), keyEquivalent: "q")

        for item in [settingsItem, switchAvatarItem, visibilityMenuItem, quitItem] {
            item.target = self
        }

        for (index, toy) in ToyCatalogue.all.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(handleThrowToy(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index // the catalogue index, read back in the handler
            throwToyMenu.addItem(item)
        }
        throwToyItem.submenu = throwToyMenu

        let menu = NSMenu()
        menu.addItem(settingsItem)
        menu.addItem(switchAvatarItem)
        menu.addItem(throwToyItem)
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
        throwToyItem.title = Strings.text(.menuThrowToy, language)
        for (index, toy) in ToyCatalogue.all.enumerated() where index < throwToyMenu.items.count {
            throwToyMenu.items[index].title = Strings.text(Self.label(for: toy), language)
        }
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
    @objc private func handleThrowToy(_ sender: NSMenuItem) {
        guard ToyCatalogue.all.indices.contains(sender.tag) else { return }
        onThrowToy?(ToyCatalogue.all[sender.tag])
    }

    /// Toy names are catalogue data; their menu labels are translated text.
    private static func label(for toy: Toy) -> L10nKey {
        switch toy.name {
        case ToyCatalogue.wand.name: return .toyWand
        default: return .toyPumpkin
        }
    }
    @objc private func handleToggleVisibility() { onToggleVisibility?() }
    @objc private func handleQuit() { onQuit?() }
}
