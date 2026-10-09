//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import Swiftfin
import XCTest

final class EpisodeContinuationTests: XCTestCase {

    func testEpisodeNineContinuesToTenBeforeSeasonTwo() {
        var season = (1...12).map { number -> BaseItemDto in
            var item = episode("ep\(number)", played: number == 9)
            item.name = "Ep\(number)_Title"
            item.seasonID = "season-one"
            item.parentIndexNumber = 1
            return item
        }.sorted { $0.name! < $1.name! }
        var premiere = episode("season-two")
        premiere.indexNumber = 1
        premiere.parentIndexNumber = 2
        premiere.seasonID = "season-two"
        let watched = season.first { $0.id == "ep9" }!
        season.append(premiere)
        XCTAssertEqual(EpisodeContinuation.nextEpisode(after: watched, in: season)?.id, "ep10")
        XCTAssertEqual(resolve(episode("wrong"), after: watched, in: season).id, "ep10")
        let ordered = EpisodeContinuation.orderedEpisodes(season)
        XCTAssertEqual(ordered.prefix(12).map(\.id), (1...12).map { "ep\($0)" })
        XCTAssertEqual(EpisodeContinuation.nextEpisode(after: ordered[11], in: ordered)?.id, premiere.id)
    }

    func testExplicitFilenameNumbersSupportCommonFormatsAndUseMetadataFirst() {
        var first = episode("first")
        first.name = "Episode 2 - Title"
        first.indexNumber = 1
        var second = episode("second")
        second.name = "s01e02_Title"
        var tenth = episode("tenth")
        tenth.name = "EP10_Title"
        XCTAssertEqual(EpisodeContinuation.orderedEpisodes([tenth, second, first]).map(\.id), [first.id, second.id, tenth.id])
    }

    func testAmbiguousNamesOrDuplicateNumbersKeepServerOrder() {
        var first = episode("first")
        first.name = "Ep1_Title"
        var unknown = episode("unknown")
        unknown.name = "Room 10"
        XCTAssertEqual(EpisodeContinuation.orderedEpisodes([unknown, first]).map(\.id), [unknown.id, first.id])
        unknown.name = "Ep1_Alternate"
        XCTAssertEqual(EpisodeContinuation.orderedEpisodes([unknown, first]).map(\.id), [unknown.id, first.id])
    }

    func testUnnumberedNextUpDoesNotSkipUnwatchedEpisode() {
        let watched = episode("eight", played: true)
        let next = episode("nine")
        let suggestion = episode("ten")

        XCTAssertEqual(resolve(suggestion, after: watched, in: [watched, next]).id, next.id)
    }

    func testNumberedSeriesKeepsServerRecommendation() {
        let watched = episode("eight", played: true)
        var suggestion = episode("ten")
        suggestion.indexNumber = 10

        XCTAssertEqual(resolve(suggestion, after: watched, in: [watched, episode("nine")]).id, suggestion.id)
    }

    func testAlreadyWatchedNextEpisodeDoesNotReplaceServerRecommendation() {
        let watched = episode("eight", played: true)
        let suggestion = episode("ten")

        XCTAssertEqual(resolve(suggestion, after: watched, in: [watched, episode("nine", played: true)]).id, suggestion.id)
    }

    func testResumableEpisodeStaysInContinueWatching() {
        let watched = episode("eight", played: true)
        var next = episode("nine")
        next.userData?.playbackPositionTicks = 100_000_000
        let suggestion = episode("ten")

        XCTAssertEqual(resolve(suggestion, after: watched, in: [watched, next]).id, suggestion.id)
    }

    func testUnnumberedContinuationCanCrossSeasonBoundary() {
        var watched = episode("finale", played: true)
        watched.parentIndexNumber = 1
        var next = episode("premiere")
        next.parentIndexNumber = 2

        XCTAssertEqual(resolve(episode("later"), after: watched, in: [watched, next]).id, next.id)
    }

    func testMissingOrUnrelatedHistoryKeepsServerRecommendation() {
        let watched = episode("eight", played: true)
        let suggestion = episode("ten")

        XCTAssertEqual(resolve(suggestion, after: watched, in: [watched]).id, suggestion.id)
        XCTAssertEqual(resolve(suggestion, after: watched, in: []).id, suggestion.id)
        XCTAssertEqual(resolve(suggestion, after: episode("other", seriesID: "other", played: true), in: [watched, episode("nine")]).id, suggestion.id)
        XCTAssertEqual(resolve(suggestion, after: episode("eight"), in: [watched, episode("nine")]).id, suggestion.id)
    }

    func testMissingEpisodeIsNotOfferedAsNextUp() {
        let watched = episode("eight", played: true)
        var next = episode("nine")
        next.locationType = .virtual
        let suggestion = episode("ten")

        XCTAssertEqual(resolve(suggestion, after: watched, in: [watched, next]).id, suggestion.id)
    }

    private func resolve(_ suggestion: BaseItemDto, after watched: BaseItemDto, in episodes: [BaseItemDto]) -> BaseItemDto {
        EpisodeContinuation.nextUpItem(
            serverSuggestion: suggestion,
            lastPlayedEpisode: watched,
            adjacentEpisodes: episodes
        )
    }

    private func episode(_ id: String, seriesID: String = "series", played: Bool = false) -> BaseItemDto {
        BaseItemDto(
            id: id,
            seriesID: seriesID,
            type: .episode,
            userData: UserItemDataDto(isPlayed: played, key: id, playbackPositionTicks: 0)
        )
    }
}
