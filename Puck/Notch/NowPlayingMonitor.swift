//
//  NowPlayingMonitor.swift
//  Puck
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  Live observation on top of MediaRemoteBridge -- boring.notch registers
//  for `kMRMediaRemoteNowPlayingInfoDidChangeNotification` via
//  DistributedNotificationCenter (it's a Darwin-wide notification, not
//  something posted within this process), then re-fetches the full info
//  dictionary on each change rather than trusting the notification's own
//  payload.
//

import Foundation

final class NowPlayingMonitor {
    var onChange: ((NowPlayingInfo?) -> Void)?

    private let bridge = MediaRemoteBridge()
    private var observer: NSObjectProtocol?

    /// False on a macOS version/security posture where the private
    /// framework's symbols didn't resolve at all -- lets AppDelegate skip
    /// building the Now Playing UI entirely rather than showing one that
    /// can never update.
    var isAvailable: Bool { bridge != nil }

    func start() {
        guard let bridge else { return }
        bridge.registerForChangeNotifications()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        refresh()
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    func togglePlayPause() { bridge?.send(.togglePlayPause) }
    func nextTrack() { bridge?.send(.nextTrack) }
    func previousTrack() { bridge?.send(.previousTrack) }

    private func refresh() {
        bridge?.fetchNowPlayingInfo { [weak self] info in
            let parsed = NowPlayingInfo.parse(from: info)
            DispatchQueue.main.async { self?.onChange?(parsed) }
        }
    }
}
