//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import XCTest

@MainActor
final class SearchTests: XCTestCase {

    func testOpeningSearchDoesNotLoadTheCatalogOrRequireAServer() async throws {
        let model = SearchViewModel()
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertFalse(model.canSearch)
        XCTAssertEqual(model.state, .initial)
        XCTAssertEqual(model.itemContentGroupViewModel.state, .initial)
        XCTAssertNil(model.error)
    }

    func testBrowsingFiltersAloneDoNotStartASearch() async throws {
        let model = SearchViewModel()
        model.filterViewModel.currentFilters = .favorites
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertFalse(model.canSearch)
        XCTAssertEqual(model.itemContentGroupViewModel.state, .initial)
    }

    func testNewQuerySearchesTheWholeCatalogAndClearingItReturnsToTheEmptyPage() async {
        let model = SearchViewModel()
        model.filterViewModel.currentFilters = .favorites
        await model.search(query: "CAD")
        XCTAssertTrue(model.canSearch)
        XCTAssertEqual(model.filterViewModel.currentFilters.query, "CAD")
        XCTAssertTrue(model.filterViewModel.currentFilters.traits.isEmpty)

        await model.search(query: "")
        XCTAssertFalse(model.canSearch)
        XCTAssertEqual(model.state, .initial)
        XCTAssertEqual(model.filterViewModel.currentFilters, .default)
    }

    func testBlankQueryDoesNotShowLoadingOrStartCatalogRequests() async throws {
        let model = SearchViewModel()
        await model.search(query: " \n  ")
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertFalse(model.canSearch)
        XCTAssertEqual(model.state, .initial)
        XCTAssertEqual(model.itemContentGroupViewModel.state, .initial)
    }

    func testFailedResultRowsAreReportedAsAnErrorRatherThanNoMatches() async throws {
        let provider = SearchContentGroupProvider()
        let groups = try await provider.makeGroups(environment: .init(filters: .init(query: "CAD")))
        XCTAssertNil(provider.resultError)
        for group in groups {
            if let group = group as? PosterGroup<ItemLibrary> {
                group.viewModel.userSession = nil
                await group.viewModel.refresh()
            } else if let group = group as? PosterGroup<PeopleLibrary> {
                group.viewModel.userSession = nil
                await group.viewModel.refresh()
            } else {
                XCTFail("Unexpected search result group")
            }
        }
        XCTAssertNotNil(provider.resultError)
    }

    func testFailedSearchCanBeClearedWithoutLeavingAnErrorOnTheEmptyPage() async {
        let model = SearchViewModel()
        await model.search(query: "CAD")
        let failure = await model.retrySearch()
        XCTAssertNotNil(failure)
        XCTAssertEqual(model.state, .error)
        XCTAssertNotNil(model.error)
        await model.search(query: "")
        XCTAssertEqual(model.state, .initial)
        XCTAssertFalse(model.canSearch)
    }
}
