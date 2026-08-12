//
//  AppDelegate+Notch.swift
//  Puck
//
//  Shared · owner: 강상우 (Sangwoo Kang) / 박해영 (Haeyoung Park)
//  boring.notch-style toy summon, 2026-08-01: a top-of-screen Dynamic Island
//  that can be expanded/collapsed and toggled on or off from Settings.
//

import AppKit
import SwiftUI

extension AppDelegate {
    // MARK: - Notch (boring.notch-style toy summon, 2026-08-01)

    /// A generic top-of-screen "Dynamic Island", present on every Mac
    /// regardless of whether it actually has a camera notch -- byeolki:
    /// "boring notch처럼 일반적인 다이내믹 아일랜드를 다는데, 이 일반적인
    /// 다이내믹 아일랜드를 펼치면 toy를 소환 시킬 수 있는 버튼이 생기게
    /// 해줘." Reuses toggleToy(_:) verbatim -- a summon from the notch and a
    /// toggle from the Settings toy grid can't leave ToyBox in different
    /// states.
    func setUpNotch() {
        let controller = NotchWindowController()
        notchWindowController = controller
        settingsStore.onNotchEnabledChanged = { [weak self] isEnabled in self?.setNotchEnabled(isEnabled) }
        if settingsStore.isNotchEnabled {
            startNotch()
        }
    }

    private func startNotch() {
        guard let controller = notchWindowController else { return }
        let statusStore = NotchStatusStore()
        notchStatusStore = statusStore

        // boring.notch's two headline widgets, ported verbatim (see
        // NowPlayingMonitor/BatteryMonitor's own doc comments) -- fresh
        // instances each time startNotch() runs, so toggling the notch back
        // on after Settings turned it off doesn't need any of this managed
        // across the gap.
        let nowPlaying = NowPlayingMonitor()
        nowPlaying.onChange = { [weak statusStore] info in statusStore?.nowPlaying = info }
        nowPlaying.start()
        nowPlayingMonitor = nowPlaying

        let battery = BatteryMonitor()
        battery.onChange = { [weak statusStore] status in statusStore?.battery = status }
        battery.start()
        batteryMonitor = battery

        let view = NotchView(
            status: statusStore,
            initialToysOut: toyBox?.outToyNames ?? [],
            onToggleToy: { [weak self] toy in self?.toggleToy(toy) ?? [] },
            onExpandedChanged: { [weak controller] isExpanded in controller?.setExpanded(isExpanded) },
            onTogglePlayPause: { [weak nowPlaying] in nowPlaying?.togglePlayPause() },
            onNextTrack: { [weak nowPlaying] in nowPlaying?.nextTrack() },
            onPreviousTrack: { [weak nowPlaying] in nowPlaying?.previousTrack() }
        )
        controller.start(contentView: NSHostingView(rootView: view))
    }

    /// Settings' toggle (byeolki, 2026-08-01: "다이내믹 아일랜드 끄고 킬 수
    /// 있는 버튼 추가해줘") -- turning it off tears the window down
    /// immediately rather than just skipping it on the next launch, and
    /// stops the two monitors so a disabled notch isn't still polling
    /// MediaRemote/IOKit in the background.
    private func setNotchEnabled(_ isEnabled: Bool) {
        guard let controller = notchWindowController else { return }
        if isEnabled {
            guard controller.window == nil else { return }
            startNotch()
        } else {
            controller.stop()
            nowPlayingMonitor?.stop()
            batteryMonitor?.stop()
            nowPlayingMonitor = nil
            batteryMonitor = nil
            notchStatusStore = nil
        }
    }
}
