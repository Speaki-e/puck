//
//  NowPlayingInfo.swift
//  Puck
//
//  Notch · owner: 박해영 (Haeyoung Park)
//  boring.notch's own decode of MediaRemote's raw now-playing dictionary,
//  ported -- byeolki, 2026-08-01: "다이내믹 아일랜드 걍 Boring Notch
//  클론코딩을 기반으로 하고".
//

import Foundation

struct NowPlayingInfo: Equatable {
    let title: String
    let artist: String?
    let isPlaying: Bool
    let artworkData: Data?

    private static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    private static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    private static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    private static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"

    /// Pure parsing seam -- `NowPlayingMonitor` supplies the real
    /// MediaRemote dictionary; a unit test supplies a literal one. `nil`
    /// title (or an empty one) means nothing is currently playing anywhere,
    /// which MediaRemote reports as an empty/title-less dictionary rather
    /// than an error.
    static func parse(from info: [String: Any]) -> NowPlayingInfo? {
        guard let title = info[titleKey] as? String, !title.isEmpty else {
            return nil
        }
        let artist = info[artistKey] as? String
        let playbackRate = info[playbackRateKey] as? Double ?? 0
        let artworkData = info[artworkDataKey] as? Data
        return NowPlayingInfo(title: title, artist: artist, isPlaying: playbackRate > 0, artworkData: artworkData)
    }
}
