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
    /// F13 (2026-07-30): PetAgentClient is a separate Dock-resident app now
    /// -- this activates/launches it (byeolki: "별도의 앱으로 해서 dock에
    /// 상시 표시"), replacing the old Option+Shift+Space-opens-the-window
    /// behavior, which is back to being just the quick-capture bubble.
    var onOpenClient: (() -> Void)?
    /// F12 (optional): the toys the pet plays with. Lowest priority, purely
    /// decorative -- see 02_pet-app.md F12.
    ///
    /// Each entry is an on/off switch for one toy rather than a "throw"
    /// action, and several can be on at once (byeolki: "메뉴를 열면 밑에
    /// 이미지와 함께 장난감 이름이 나오고 그걸 눌러서 나오게하고 다시 눌러서
    /// 없애는", 2026-07-30). AppDelegate answers with what is out afterwards,
    /// via `setToysOut` -- the menu never assumes its own toggle took.
    var onToggleToy: ((Toy) -> Void)?
    /// byeolki's request, 2026-07-29: hide/show the pet without quitting.
    var onToggleVisibility: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private let settingsItem: NSMenuItem
    private let switchAvatarItem: NSMenuItem
    private let openClientItem: NSMenuItem
    /// One entry per toy in the catalogue, built once -- adding a toy to
    /// ToyCatalogue puts it in this menu with no further wiring.
    private let toysItem: NSMenuItem
    private let toysMenu = NSMenu()
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
        openClientItem = NSMenuItem(title: "", action: #selector(handleOpenClient), keyEquivalent: "")
        toysItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        visibilityMenuItem = NSMenuItem(title: "", action: #selector(handleToggleVisibility), keyEquivalent: "h")
        quitItem = NSMenuItem(title: "", action: #selector(handleQuit), keyEquivalent: "q")

        for item in [settingsItem, switchAvatarItem, openClientItem, visibilityMenuItem, quitItem] {
            item.target = self
        }

        for (index, toy) in ToyCatalogue.all.enumerated() {
            let item = NSMenuItem(title: "", action: #selector(handleToggleToy(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index // the catalogue index, read back in the handler
            item.image = ToyThumbnail.image(for: toy)
            toysMenu.addItem(item)
        }
        toysItem.submenu = toysMenu

        let menu = NSMenu()
        menu.addItem(openClientItem)
        menu.addItem(settingsItem)
        menu.addItem(switchAvatarItem)
        menu.addItem(toysItem)
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
        openClientItem.title = Strings.text(.menuOpenClient, language)
        settingsItem.title = Strings.text(.menuSettings, language)
        switchAvatarItem.title = Strings.text(.menuSwitchAvatar, language)
        toysItem.title = Strings.text(.menuToys, language)
        for (index, toy) in ToyCatalogue.all.enumerated() where index < toysMenu.items.count {
            toysMenu.items[index].title = Strings.text(Self.label(for: toy), language)
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
    @objc private func handleOpenClient() { onOpenClient?() }
    @objc private func handleToggleToy(_ sender: NSMenuItem) {
        guard ToyCatalogue.all.indices.contains(sender.tag) else { return }
        onToggleToy?(ToyCatalogue.all[sender.tag])
    }

    /// Ticks the toys that are currently out. Same contract as
    /// `setVisibilityLabel`: pushed by AppDelegate from real state, so a
    /// toggle that didn't happen doesn't leave a checkmark lying about.
    func setToysOut(_ names: Set<String>) {
        for (index, toy) in ToyCatalogue.all.enumerated() where index < toysMenu.items.count {
            toysMenu.items[index].state = names.contains(toy.name) ? .on : .off
        }
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
