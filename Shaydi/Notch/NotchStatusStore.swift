//
//  NotchStatusStore.swift
//  Shaydi
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Live-updating state NotchView observes -- NowPlayingMonitor/
//  BatteryMonitor push into this from AppDelegate; unlike toysOut (which
//  NotchView drives itself in response to its own button taps), these two
//  change from outside the view entirely (another app changes track, the
//  battery drains), so they need an ObservableObject rather than a plain
//  `var` seed.
//

import Foundation

final class NotchStatusStore: ObservableObject {
    @Published var nowPlaying: NowPlayingInfo?
    @Published var battery: BatteryStatus?
}
