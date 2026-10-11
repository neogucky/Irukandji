//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import Foundation
import JellyfinAPI
import XCTest

@MainActor
final class HomeDiscoveryTests: XCTestCase {
    func testFixedRowsKeepOrderAndOnlyContinueAndNextUpAllowFewerThanSix() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let session = UserSession(
            server: ServerState(urls: [url], currentURL: url, name: "Server", id: "server", userIDs: []),
            user: UserState(id: "user", serverID: "server", username: "User")
        )
        let groups = TVHomeRows.makeGroups(userSession: session, libraries: [])
        XCTAssertEqual(Array(groups.prefix(4)).map(\.id), TVHomeRows.fixedIDs)
        XCTAssertTrue(groups.last is HomeDiscoveryContentGroup)
        let nextUp = try XCTUnwrap(groups[1] as? HomePrefetchRow<NextUpLibrary>).group
        nextUp.viewModel.elements.append(BaseItemDto(id: "episode", name: "Episode", type: .episode))
        XCTAssertTrue(nextUp._shouldBeResolved)
        let newMovies = try XCTUnwrap(groups[2] as? HomePrefetchRow<HomeRowLibrary>).group
        newMovies.viewModel.elements.append(contentsOf: items(count: 5))
        XCTAssertFalse(newMovies._shouldBeResolved)
        try newMovies.viewModel.elements.append(XCTUnwrap(items(count: 6).last))
        XCTAssertTrue(newMovies._shouldBeResolved)
        let newShows = try XCTUnwrap(groups[3] as? HomePrefetchRow<HomeRowLibrary>).group
        XCTAssertEqual(newShows.library.row.itemType, .series)
        XCTAssertEqual(newShows.environment.minimumItemCount, 6)
    }

    func testRefreshDoesNotLoadUnvisitedRecipesAndFirstBatchIsBounded() async {
        var requests: [String] = []
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 30), shuffle: false) { row in
            requests.append(row.id)
            return self.items(count: 6)
        }
        await model.refresh()
        XCTAssertTrue(requests.isEmpty)
        await model.loadMore()
        // Requests run concurrently; their completion order is not a contract.
        XCTAssertEqual(Set(requests), ["row-0", "row-1", "row-2"])
        XCTAssertEqual(model.rows.map(\.id), ["row-0", "row-1", "row-2"])
        XCTAssertTrue(model.hasMore)
    }

    func testSparseAndDuplicateRowsAreSkippedWithoutEmptyHeadings() async {
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 3), shuffle: false) { row in
            if row.id == "row-0" {
                return self.items(count: 5)
            }
            if row.id == "row-1" {
                return Array(repeating: self.items(count: 1)[0], count: 8)
            }
            return self.items(count: 6)
        }
        await model.loadMore()
        XCTAssertEqual(model.rows.map(\.id), ["row-2"])
        XCTAssertFalse(model.hasMore)
    }

    func testScanningContinuesPastAWholeBatchOfSparseRows() async {
        var requests = 0
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 6), shuffle: false) { row in
            requests += 1
            return self.items(count: row.id < "row-3" ? 5 : 6)
        }
        await model.loadMore()
        XCTAssertEqual(requests, 6)
        XCTAssertEqual(model.rows.map(\.id), ["row-3", "row-4", "row-5"])
    }

    func testConcurrentPrefetchRequestsShareOneBatch() async {
        var requests = 0
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 30), shuffle: false) { _ in
            requests += 1
            try await Task.sleep(for: .milliseconds(20))
            return self.items(count: 6)
        }
        async let first: Void = model.loadMore()
        async let second: Void = model.loadMore()
        _ = await (first, second)
        XCTAssertEqual(requests, 3)
        XCTAssertEqual(model.rows.count, 3)
    }

    func testOutageCanRetrySameCandidatesAndIndividualFailureDoesNotHideGoodRows() async {
        var offline = true
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 3), shuffle: false) { row in
            if offline || row.id == "row-1" {
                throw URLError(.notConnectedToInternet)
            }
            return self.items(count: 6)
        }
        await model.loadMore()
        XCTAssertTrue(model.hasLoadError)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(model.hasMore)
        offline = false
        await model.loadMore()
        XCTAssertFalse(model.hasLoadError)
        XCTAssertEqual(model.rows.map(\.id), ["row-0", "row-2"])
        XCTAssertFalse(model.hasMore)
    }

    func testReturningFromDetailsRefreshesOnlyRequestedRowAndPreservesCardsAndOrder() async {
        var requests: [String] = []
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 30), shuffle: false, loader: { _ in
            self.items(count: 6)
        }, refreshLoader: { row, items in
            requests.append(row.id)
            return items.reversed()
        })
        await model.loadMore()
        let previousRows = model.rows.map(\.id)
        let previousItems = model.rows[0].group.viewModel.elements.map(\.id)
        await model.refresh()
        XCTAssertTrue(requests.isEmpty)
        await model.refreshRow("row-0")
        XCTAssertEqual(requests, ["row-0"])
        XCTAssertEqual(model.rows.map(\.id), previousRows)
        XCTAssertEqual(model.rows[0].group.viewModel.elements.map(\.id), previousItems)
    }

    func testDiscoveryShufflesEligibleCardsBeforeLimitingAndKeepsOrderOnReturn() async throws {
        var orderingCalls = 0
        let rankedItems = items(count: 30)
        let model = HomeDiscoveryViewModel(catalog: recipes(count: 1), shuffle: false, loader: { _ in
            rankedItems + [BaseItemDto(id: "wrong-type", type: .series)]
        }, refreshLoader: { _, items in
            items.reversed()
        }, itemOrder: { items in
            orderingCalls += 1
            XCTAssertEqual(items.count, 30)
            return items.reversed()
        })
        await model.loadMore()
        let row = try XCTUnwrap(model.rows.first)
        let ids = row.group.viewModel.elements.map(\.id)
        XCTAssertEqual(ids, rankedItems.reversed().prefix(HomeDiscoveryRow.itemLimit).map(\.id))
        XCTAssertEqual(orderingCalls, 1)
        await model.refresh()
        await model.refreshRow(row.id)
        XCTAssertEqual(row.group.viewModel.elements.map(\.id), ids)
        XCTAssertEqual(orderingCalls, 1)
    }

    func testRecipesUseCorrectYearRangeTypeRatingAndAdditionDate() throws {
        let decade = try XCTUnwrap(HomeDiscoveryRow.catalog.first { $0.id == "shows-1990s" })
        let parameters = decade.parameters(userID: "user", parentID: "shows", limit: 24)
        XCTAssertEqual(parameters.years, Array(1990 ..< 2000))
        XCTAssertEqual(parameters.includeItemTypes, [.series])
        XCTAssertEqual(parameters.parentID, "shows")
        XCTAssertEqual(parameters.limit, 24)
        let rating = try XCTUnwrap(HomeDiscoveryRow.catalog.first { $0.id == "movies-top-rated" })
        XCTAssertEqual(rating.parameters(userID: "user", parentID: nil, limit: 24).sortBy?.first, .communityRating)
        XCTAssertEqual(rating.parameters(userID: "user", parentID: nil, limit: 24).minCommunityRating, 0.1)
        XCTAssertEqual(HomeDiscoveryRow.newMovies.parameters(userID: "user", parentID: nil, limit: 24).sortBy?.first, .dateCreated)
        XCTAssertEqual(Set(HomeDiscoveryRow.catalog.map(\.id)).count, HomeDiscoveryRow.catalog.count)
    }

    func testHistorySeedsSeriesOnceAndUsesOnlyWatchedTitles() {
        var episode = BaseItemDto(id: "ep-1", name: "Episode", seriesID: "series", seriesName: "A series", type: .episode)
        episode.userData = UserItemDataDto(isPlayed: true, key: "ep-1")
        var another = episode
        another.id = "ep-2"
        var movie = items(count: 1)[0]
        movie.userData = UserItemDataDto(isPlayed: true, key: "item-0")
        let suggestions = HomeDiscoveryRow.similarRows(recentlyPlayed: [episode, another, items(count: 2)[1], movie])
        XCTAssertEqual(suggestions.map(\.similarItemID), ["series", movie.id])
        XCTAssertEqual(suggestions.first?.itemType, .series)
        XCTAssertEqual(suggestions.first?.title, "Because you watched A series")
    }

    func testEligibilityRejectsWrongTypesUnavailableFutureAndWatchedTitles() {
        let row = HomeDiscoveryRow(id: "unseen", title: "Unseen", itemType: .movie, isPlayed: false, similarItemID: "self")
        var watched = BaseItemDto(id: "watched", type: .movie)
        watched.userData = UserItemDataDto(isPlayed: true, key: "watched")
        let candidates = [
            BaseItemDto(id: "self", type: .movie),
            BaseItemDto(id: "series", type: .series),
            BaseItemDto(id: "missing", locationType: .virtual, type: .movie),
            BaseItemDto(id: "future", premiereDate: .now.addingTimeInterval(86400), type: .movie),
            BaseItemDto(type: .movie), watched
        ] + items(count: 6)
        XCTAssertEqual(row.normalized(candidates).count, 6)
    }

    private func recipes(count: Int) -> [HomeDiscoveryRow] {
        (0 ..< count).map { .init(id: "row-\($0)", title: "Row \($0)", itemType: .movie) }
    }

    private func items(count: Int) -> [BaseItemDto] {
        (0 ..< count).map { .init(id: "item-\($0)", name: "Movie \($0)", type: .movie) }
    }
}
