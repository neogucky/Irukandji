//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import Alphane
import TVServices
import XCTest

@MainActor
final class TopShelfTests: XCTestCase {
    func testSharedCacheUsesTVOSWritableLibraryDirectory() throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: container) }
        let storage = TopShelfStorage(appGroupContainer: container)
        XCTAssertEqual(storage.directory, container.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true))
        try storage.activate(serverID: "server", userID: "user")
        let expected = snapshot()
        try storage.write(expected)
        XCTAssertEqual(storage.read(), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: container.appendingPathComponent("TopShelf").path))
    }

    func testResumeWinsAndEachSeriesAppearsOnlyOnce() {
        let resume = episode("resume", seriesID: "series")
        let next = episode("next", seriesID: "series")
        let other = episode("other", seriesID: "other-series")
        let movie = BaseItemDto(id: "movie", name: "Movie", type: .movie)
        let candidates = TopShelfService.candidates(resume: [resume], nextUp: [next, other], latest: [movie, resume])
        XCTAssertEqual(candidates.map(\.item.id), ["resume", "other", "movie"])
        XCTAssertTrue(candidates[0].contextTitle.contains(L10n.continue))
        XCTAssertTrue(candidates[1].contextTitle.contains(L10n.nextUp))
    }

    func testMissingWatchedUnairedAndNonVideoItemsAreExcluded() {
        var missing = episode("missing", seriesID: "one")
        missing.locationType = .virtual
        var watched = episode("watched", seriesID: "two")
        watched.userData = UserItemDataDto(isPlayed: true, key: "watched")
        var unaired = episode("unaired", seriesID: "three")
        unaired.premiereDate = Date.now.addingTimeInterval(86400)
        let audio = BaseItemDto(id: "audio", name: "Audio", type: .audio)
        XCTAssertTrue(TopShelfService.candidates(resume: [missing, watched], nextUp: [unaired], latest: [audio]).isEmpty)
    }

    func testCarouselUsesCachedArtworkAndDistinctPlayAndInfoLinks() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try storage.clear()
        try Data([1]).write(to: storage.directory.appendingPathComponent("art.jpg"))
        try storage.write(snapshot())
        let carousel = try XCTUnwrap(storage.carousel())
        XCTAssertEqual(carousel.style, .details)
        let item = try XCTUnwrap(carousel.items.first)
        XCTAssertEqual(item.title, "Episode")
        XCTAssertEqual(item.contextTitle, "Next up")
        XCTAssertEqual(item.playAction?.url.absoluteString, "alphane://server/user/play/episode")
        XCTAssertEqual(item.displayAction?.url.absoluteString, "alphane://server/user/item/episode")
        XCTAssertTrue(try XCTUnwrap(item.imageURL(for: .screenScale1x)).isFileURL)
        XCTAssertEqual(item.imageURL(for: .screenScale1x), item.imageURL(for: .screenScale2x))
    }

    func testMissingOrExpiredArtworkFallsBackToStaticBranding() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try storage.write(snapshot())
        XCTAssertNil(storage.carousel())
        try Data([1]).write(to: storage.directory.appendingPathComponent("art.jpg"))
        XCTAssertNil(storage.carousel(now: Date.now.addingTimeInterval(8 * 86400)))
        try Data("invalid json".utf8).write(to: storage.directory.appendingPathComponent("content.json"))
        XCTAssertNil(storage.carousel())
    }

    func testSigningOutOrSwitchingAccountsRemovesCachedContent() throws {
        let storage = temporaryStorage()
        defer { try? FileManager.default.removeItem(at: storage.directory) }
        try storage.write(snapshot())
        try Data([1]).write(to: storage.directory.appendingPathComponent("art.jpg"))
        try storage.activate(serverID: "server", userID: "user")
        XCTAssertNotNil(storage.read())
        try storage.activate(serverID: "server", userID: "other-user")
        XCTAssertNil(storage.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.directory.appendingPathComponent("art.jpg").path))
        try storage.write(snapshot())
        try storage.clear()
        XCTAssertNil(storage.read())
    }

    func testCacheNeverAllowsArtworkPathTraversalOrMalformedActionIDs() {
        let storage = temporaryStorage()
        XCTAssertNil(storage.artworkURL(fileName: "../art.jpg"))
        XCTAssertNil(storage.artworkURL(fileName: "/art.jpg"))
        XCTAssertNil(snapshot().actionURL(itemID: "item?play=anything", play: true))
    }

    func testDeepLinksDistinguishPlaybackFromDetailsAndPreserveLegacySchemes() throws {
        let info = try XCTUnwrap(DeepLink(URL(string: "alphane://server/user/item/episode")!))
        let play = try XCTUnwrap(DeepLink(URL(string: "alphane://server/user/play/episode")!))
        XCTAssertEqual(info.destination, .item(id: "episode"))
        XCTAssertEqual(play.destination, .play(id: "episode"))
        XCTAssertEqual(play.serverID, "server")
        XCTAssertEqual(play.userID, "user")
        XCTAssertNotNil(DeepLink(URL(string: "jellyfin://server/user/item/episode")!))
        XCTAssertNil(DeepLink(URL(string: "https://server/user/play/episode")!))
        XCTAssertNil(DeepLink(URL(string: "alphane://server/user/play/episode?unexpected=true")!))
    }

    private func episode(_ id: String, seriesID: String) -> BaseItemDto {
        var item = BaseItemDto(id: id, name: id, type: .episode)
        item.seriesID = seriesID
        item.seriesName = "Series"
        return item
    }

    private func temporaryStorage() -> TopShelfStorage {
        TopShelfStorage(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    private func snapshot() -> TopShelfSnapshot {
        TopShelfSnapshot(serverID: "server", userID: "user", updatedAt: .now, entries: [
            TopShelfEntry(itemID: "episode", title: "Episode", contextTitle: "Next up", summary: "Summary", duration: 300, artworkFileName: "art.jpg"),
        ])
    }
}
