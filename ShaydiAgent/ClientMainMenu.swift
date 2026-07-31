//
//  ClientMainMenu.swift
//  ShaydiAgent
//
//  F13 · owner: 박해영 (Haeyoung Park)
//  ShaydiAgent's main menu, built in code.
//
//  byeolki (2026-07-30): "client 커맨드 q처럼 기본적인 커맨드 다 먹히게".
//  An AppKit app assembled by hand (no MainMenu.xib -- this project generates
//  its Xcode project and has no nibs) starts with *no* main menu at all, and
//  every standard shortcut is a menu item's key equivalent: with no menu,
//  Cmd+Q/W/M and even Cmd+C/V in the chat's text field are dead keys. This is
//  the smallest menu that makes them work again. ShaydiTests compiles this
//  one file directly (see project.yml) rather than reaching it through the
//  Shaydi target, which never uses it.
//
//  Titles are Korean like the rest of the client window; it has no
//  AppLanguage plumbing yet (see ClientWindowStore's note).
//

import AppKit

enum ClientMainMenu {
    static func make(appName: String = "ShaydiAgent") -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenu: appMenu(appName: appName))
        mainMenu.addItem(submenu: editMenu())
        mainMenu.addItem(submenu: windowMenu())
        return mainMenu
    }

    private static func appMenu(appName: String) -> NSMenu {
        // macOS titles the first menu with the app name itself, whatever this
        // menu's own title is.
        let menu = NSMenu(title: appName)
        menu.addItem(title: "\(appName) 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        menu.addItem(.separator())
        menu.addItem(title: "\(appName) 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(
            title: "다른 항목 가리기",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        )
        menu.addItem(title: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        // Quits this app only. The pet is a separate process (Shaydi) and
        // keeps running -- byeolki, same day: "이 새로 열린창을 최소화하거나
        // 종료하게 된다고해서 펫이 사라지면 안됨".
        menu.addItem(title: "\(appName) 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// The chat input is an ordinary NSTextField underneath: without these
    /// items, copy/paste/select-all inside it do nothing.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "편집")
        menu.addItem(title: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(title: "다시 실행", action: Selector(("redo:")), keyEquivalent: "z", modifiers: [.command, .shift])
        menu.addItem(.separator())
        menu.addItem(title: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(title: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(title: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(title: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "윈도우")
        menu.addItem(title: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(title: "확대/축소", action: #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        // Closing the window doesn't quit: applicationShouldTerminateAfterLast-
        // WindowClosed is false, and the Dock icon reopens it.
        menu.addItem(title: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }

    @discardableResult
    func addItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        addItem(item)
        return item
    }
}
