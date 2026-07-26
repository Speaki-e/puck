//
//  PetAgentApp.swift
//  PetAgent
//
//  공통 · 담당: 강상우/박해영
//  @main 진입점, LSUIElement 메뉴바 상주 라이프사이클 부트스트랩
//
//  NOTE: 나머지 초기화 순서(권한 자가진단 → Overlay → BridgeServer → GlobalHotkeyManager)는
//  각 모듈이 구현되는 대로 AppDelegate에 연결한다.

import AppKit

@main
enum PetAgentApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
