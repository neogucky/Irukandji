//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import JellyfinAPI
import XCTest

@MainActor
final class UpstreamMergeTests: XCTestCase {

    func testSharedMetadataUpdatesPreviewWithoutChangingFocusedIdentity() throws {
        let store = ItemStore()
        let original = resumable("movie", title: "Old title")
        let record = try store.record(for: original)
        let entry = ItemEntry(item: record)
        var selection = CinematicItemSelection<ItemEntry>()
        selection.focus(entry, in: [entry])
        var updated = original
        updated.name = "Updated title"
        updated.overview = "Updated description"
        try store.merge(ItemPatch.snapshot(updated), token: store.beginRequest())

        XCTAssertEqual(selection.selectedID, entry.id)
        XCTAssertEqual(selection.item(in: [entry])?.snapshot.name, updated.name)
        XCTAssertEqual(selection.item(in: [entry])?.snapshot.overview, updated.overview)
    }

    func testFinishedContinueItemRejectsLateProgressAndMovesPreviewToNextCard() throws {
        let store = ItemStore()
        let cad = resumable("cad", title: "CAD")
        let cadRecord = try store.record(for: cad)
        let movieRecord = try store.record(for: resumable("movie", title: "Movie"))
        let entries = [ItemEntry(item: cadRecord), ItemEntry(item: movieRecord)]
        var selection = CinematicItemSelection<ItemEntry>()
        selection.focus(entries[0], in: entries)

        let oldRequest = try store.beginRequest()
        let completionRequest = try store.beginRequest()
        var completed = cad
        completed.userData?.isPlayed = true
        completed.userData?.playbackPositionTicks = 0
        try store.merge(ItemPatch.snapshot(completed), token: completionRequest)
        try store.merge(ItemPatch.snapshot(cad), token: oldRequest)

        let remaining = entries.filter { ResumeItemsLibrary().includes($0, environment: .default) }
        XCTAssertEqual(remaining.map(\.itemID), ["movie"])
        XCTAssertEqual(selection.item(in: remaining)?.itemID, "movie")
        XCTAssertEqual(cadRecord.value?.userData?.isPlayed, true)
        XCTAssertEqual(cadRecord.value?.userData?.playbackPositionTicks, 0)
    }

    func testCachedDiscoverySnapshotCannotUndoConfirmedWatchedState() throws {
        let store = ItemStore()
        let cached = resumable("cad", title: "CAD")
        let record = try store.record(for: cached)
        var watched = cached
        watched.userData?.isPlayed = true
        watched.userData?.playbackPositionTicks = 0
        try store.merge(ItemPatch.snapshot(watched), token: store.beginRequest())

        let redisplayed = try store.record(for: cached)
        XCTAssertTrue(redisplayed === record)
        XCTAssertEqual(redisplayed.value?.userData?.isPlayed, true)
        XCTAssertEqual(redisplayed.value?.userData?.playbackPositionTicks, 0)
    }

    private func resumable(_ id: String, title: String) -> BaseItemDto {
        BaseItemDto(id: id, name: title, type: .movie,
                    userData: UserItemDataDto(isPlayed: false, key: id, playbackPositionTicks: 100_000_000))
    }
}
