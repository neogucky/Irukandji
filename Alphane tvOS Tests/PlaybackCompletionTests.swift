//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import Alphane
import XCTest

@MainActor
final class PlaybackCompletionTests: XCTestCase {

    func testNaturalEndingWaitsForStaleWatchedStateToSettle() async throws {
        var calls = 0
        let result = try await PlaybackCompletion.refreshedItem(stoppedAt: 3_102_100_000) {
            calls += 1
            return self.item(played: calls > 1)
        } pause: {}
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(result.userData?.isPlayed, true)
        XCTAssertEqual(result.userData?.playbackPositionTicks, 0)
    }

    func testNaturalEndingDoesNotKeepStaleResumePositionAfterBoundedRetries() async throws {
        var calls = 0
        let result = try await PlaybackCompletion.refreshedItem(stoppedAt: 3_102_100_000) {
            calls += 1
            return self.item(played: false)
        } pause: {}
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(result.userData?.isPlayed, true)
        XCTAssertEqual(result.userData?.playbackPositionTicks, 0)
    }

    func testStoppingHalfwayDoesNotMarkEpisodeWatchedOrRetry() async throws {
        var calls = 0
        let result = try await PlaybackCompletion.refreshedItem(stoppedAt: 1_503_860_000) {
            calls += 1
            return self.item(played: false)
        } pause: {}
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result.userData?.isPlayed, false)
        XCTAssertEqual(result.userData?.playbackPositionTicks, 1_503_860_000)
    }

    func testEndingARewatchClearsStaleResumePositionWithoutRetrying() async throws {
        var watched = item(played: true)
        watched.userData?.playbackPositionTicks = 1_503_860_000
        var calls = 0
        let result = try await PlaybackCompletion.refreshedItem(stoppedAt: 3_102_100_000) {
            calls += 1
            return watched
        } pause: { XCTFail("Already-watched state needs no retry") }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(result.userData?.playbackPositionTicks, 0)
        XCTAssertTrue(PlaybackCompletion.shouldPreferNextEpisode(
            after: result, stoppedAt: 3_102_100_000, nextEpisode: nextEpisode
        ))
    }

    func testNextFocusRequiresFinishingThisViewingAndAnAvailableNextEpisode() {
        let watched = item(played: true)
        XCTAssertTrue(PlaybackCompletion.shouldPreferNextEpisode(
            after: watched, stoppedAt: watched.runTimeTicks, nextEpisode: nextEpisode
        ))
        // Simply opening an episode, even a watched one, keeps Play/Continue selected.
        XCTAssertFalse(PlaybackCompletion.shouldPreferNextEpisode(
            after: watched, stoppedAt: nil, nextEpisode: nextEpisode
        ))
        XCTAssertFalse(PlaybackCompletion.shouldPreferNextEpisode(
            after: watched, stoppedAt: 1_503_860_000, nextEpisode: nextEpisode
        ))
        var resumable = watched
        resumable.userData?.playbackPositionTicks = 1_503_860_000
        XCTAssertFalse(PlaybackCompletion.shouldPreferNextEpisode(
            after: resumable, stoppedAt: resumable.runTimeTicks, nextEpisode: nextEpisode
        ))
        XCTAssertFalse(PlaybackCompletion.shouldPreferNextEpisode(
            after: watched, stoppedAt: watched.runTimeTicks, nextEpisode: nil
        ))
        var movie = watched
        movie.type = .movie
        XCTAssertFalse(PlaybackCompletion.shouldPreferNextEpisode(
            after: movie, stoppedAt: movie.runTimeTicks, nextEpisode: nextEpisode
        ))
    }

    func testOnlyTheMatchingStopUpdatesDetailPlaybackFocusContext() {
        let provider = ItemContentGroupProvider(item: item(played: false))
        var report = PlaybackStopInfo()
        report.itemID = "nine"
        report.positionTicks = 1_503_860_000
        XCTAssertTrue(provider.prepareForPlaybackStop(report))
        XCTAssertEqual(provider.lastPlaybackStopPosition, report.positionTicks)
        report.itemID = "other-episode"
        report.positionTicks = 3_102_100_000
        XCTAssertFalse(provider.prepareForPlaybackStop(report))
        XCTAssertEqual(provider.lastPlaybackStopPosition, 1_503_860_000)
    }

    private var nextEpisode: BaseItemDto {
        BaseItemDto(id: "ten", type: .episode)
    }

    func testUnknownRuntimeAndUnrelatedStopCannotCompleteTheDetailPage() {
        var episode = item(played: false)
        episode.runTimeTicks = nil
        XCTAssertFalse(PlaybackCompletion.reachedEnd(of: episode, at: 3_102_100_000))
        let provider = ItemContentGroupProvider(item: episode)
        var report = PlaybackStopInfo()
        report.itemID = "different-episode"
        report.positionTicks = 3_102_100_000
        XCTAssertFalse(provider.prepareForPlaybackStop(report))
    }

    private func item(played: Bool) -> BaseItemDto {
        BaseItemDto(
            id: "nine", runTimeTicks: 3_102_100_000, type: .episode,
            userData: UserItemDataDto(isPlayed: played, key: "nine", playbackPositionTicks: played ? 0 : 1_503_860_000)
        )
    }
}
