//
//  MenuBarController.swift
//  PetAgent
//
//  Shared · owner: Sangwoo Kang / Haeyoung Park
//  The status item, and the panel it drops down.
//
//  2026-07-31 (byeolki: "이 설정 이거 위에 아이콘 누르면 바로 나오게 그
//  창을"): this used to be an NSMenu whose "설정…" item opened a separate
//  settings window. Now the icon drops the settings panel itself, the way
//  the pokoPet reference does -- one click, no menu in between.
//
//  Everything the menu used to carry lives in that panel instead: the toy
//  switches are its tile grid, and open-chat / hide / quit are the action
//  rows at its foot. So there are no NSMenuItem titles left to translate,
//  which is also why `applyLanguage` is gone -- the panel is SwiftUI and
//  recomputes its own text.
//

import AppKit

final class MenuBarController {
    /// Built afresh on every open rather than cached: the panel shows live
    /// state (which toys are out, whether Accessibility has been granted
    /// since last time, the current language), none of which a retained view
    /// would pick up.
    var makePopoverContent: (() -> NSViewController?)?

    /// Kept in step with SettingsView's own frame -- the popover and the view
    /// inside it have to agree or the panel opens clipped.
    static let panelSize = NSSize(width: 360, height: 560)

    private let statusItem: NSStatusItem
    private let popover = NSPopover()

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "PetAgent")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        // Closes when the user clicks away, like every other menu bar panel.
        popover.behavior = .transient
    }

    /// Second click on the icon dismisses, matching how a menu behaved.
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        guard !popover.isShown else {
            popover.performClose(nil)
            return
        }
        guard let content = makePopoverContent?() ?? nil else { return }
        content.preferredContentSize = Self.panelSize
        popover.contentViewController = content
        // Both, and before showing: without an explicit contentSize the
        // popover sized itself from a partially-laid-out hosting view and
        // opened clipped, showing the panel's bottom half with its header
        // off the top of the screen.
        popover.contentSize = Self.panelSize
        // An LSUIElement app doesn't become active just because its status
        // item was clicked, and an inactive popover's text fields never take
        // keystrokes -- without this the custom emotion name field can't be
        // typed into at all. Ahead of show(), so the popover isn't laid out
        // once and then re-laid-out by the activation.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// For panel actions that lead somewhere else (opening the client app),
    /// where leaving the panel hanging over the result reads as a bug.
    func closePopover() {
        popover.performClose(nil)
    }
}
