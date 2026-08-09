//
//  ClientMainMenuTests.swift
//  Puck
//
//  F13 test · owner: 박해영 (Haeyoung Park)
//  byeolki: "client 커맨드 q처럼 기본적인 커맨드 다 먹히게" -- PuckClient
//  shipped with no main menu at all, which on AppKit means no key
//  equivalents either. These pin the shortcuts that were missing.
//

import AppKit
import XCTest

final class ClientMainMenuTests: XCTestCase {
    private func shortcuts(in menu: NSMenu) -> [String: NSEvent.ModifierFlags] {
        var found: [String: NSEvent.ModifierFlags] = [:]
        for item in menu.items {
            if !item.keyEquivalent.isEmpty {
                found[item.keyEquivalent] = item.keyEquivalentModifierMask
            }
            if let submenu = item.submenu {
                found.merge(shortcuts(in: submenu)) { existing, _ in existing }
            }
        }
        return found
    }

    func test_make_bindsTheStandardShortcuts() {
        let found = shortcuts(in: ClientMainMenu.make())

        // Quit/close/minimize plus the clipboard set the chat input needs,
        // plus Settings (","), the standard Mac shortcut for it.
        for key in ["q", "w", "m", "x", "c", "v", "a", "z", "h", ","] {
            XCTAssertNotNil(found[key], "Cmd+\(key.uppercased()) has no menu item, so it can't fire")
            XCTAssertTrue(found[key]?.contains(.command) ?? false, "Cmd+\(key.uppercased()) must be a Command shortcut")
        }
    }

    // byeolki, 2026-08-02: "기존 셰이디앱에 있던 에이전트 관련 설정은 전부
    // 셰이디에이전트 설정으로 옮기고" -- the item this shortcut fires.
    func test_make_settingsItem_targetsTheResponderChain() {
        let settings = ClientMainMenu.make().items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { $0.keyEquivalent == "," }

        XCTAssertEqual(settings?.action, Selector(("showSettings:")))
        // nil target = go up the responder chain to AppDelegate, same as Quit.
        XCTAssertNil(settings?.target)
    }

    func test_make_wiresQuitToTheApplicationItself() {
        let quit = ClientMainMenu.make().items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { $0.keyEquivalent == "q" }

        XCTAssertEqual(quit?.action, #selector(NSApplication.terminate(_:)))
        // nil target = go up the responder chain to NSApp, which is what
        // makes Cmd+Q work from any window.
        XCTAssertNil(quit?.target)
    }
}
