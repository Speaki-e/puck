//
//  NowPlayingInfoTests.swift
//  Puck
//
//  Notch test · owner: 박해영 (Haeyoung Park)
//  boring.notch decodes MediaRemote's raw now-playing dictionary into a
//  typed struct; this is that same seam, testable without ever calling the
//  private framework itself.
//

import XCTest
@testable import Puck

final class NowPlayingInfoTests: XCTestCase {
    private let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    private let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    private let rateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    private let artworkKey = "kMRMediaRemoteNowPlayingInfoArtworkData"

    func test_parses_titleArtistAndPlayingState() {
        let info = NowPlayingInfo.parse(from: [titleKey: "Song", artistKey: "Artist", rateKey: 1.0])

        XCTAssertEqual(info?.title, "Song")
        XCTAssertEqual(info?.artist, "Artist")
        XCTAssertEqual(info?.isPlaying, true)
    }

    func test_zeroPlaybackRate_isPaused() {
        let info = NowPlayingInfo.parse(from: [titleKey: "Song", rateKey: 0.0])

        XCTAssertEqual(info?.isPlaying, false)
    }

    func test_missingPlaybackRate_defaultsToPaused() {
        let info = NowPlayingInfo.parse(from: [titleKey: "Song"])

        XCTAssertEqual(info?.isPlaying, false)
    }

    /// Nothing is currently playing anywhere -- MediaRemote returns an
    /// empty (or title-less) dictionary rather than throwing.
    func test_missingTitle_returnsNil() {
        XCTAssertNil(NowPlayingInfo.parse(from: [artistKey: "Artist"]))
    }

    func test_emptyTitle_returnsNil() {
        XCTAssertNil(NowPlayingInfo.parse(from: [titleKey: ""]))
    }

    func test_artworkData_carriedThrough() {
        let data = Data([0x01, 0x02, 0x03])
        let info = NowPlayingInfo.parse(from: [titleKey: "Song", artworkKey: data])

        XCTAssertEqual(info?.artworkData, data)
    }

    func test_missingArtworkData_isNil() {
        let info = NowPlayingInfo.parse(from: [titleKey: "Song"])

        XCTAssertNil(info?.artworkData)
    }
}
