//
//  AppDelegate.swift
//  PetAgent
//
//  공통 · 담당: 강상우/박해영
//  권한 자가진단 → 오버레이/브릿지서버/전역단축키 초기화 순서 조정
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // TODO: PermissionOnboarding → OverlayWindowController → BridgeServer → GlobalHotkeyManager
        // 순서로 초기화한다. 각 모듈이 구현되는 대로 하나씩 연결한다.
    }
}
