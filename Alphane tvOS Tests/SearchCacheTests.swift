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
final class SearchCacheTests: XCTestCase {

    func testCompleteSearchNarrowsImmediatelyAndReusesArtworkRecordsWithoutRequests() async throws {
        let model = model()
        await model.search(query: "kill")
        let failure = await model.retrySearch()
        XCTAssertNil(failure)
        XCTAssertEqual(SearchProtocol.stub.requests.count, 10)
        let previous = try XCTUnwrap(movieGroup(model)?.viewModel.elements.first(where: { $0.itemID == "killer" }))

        await model.search(query: "killer")
        XCTAssertEqual(model.state, .initial)
        let local = try XCTUnwrap(cachedMovieGroup(model))
        XCTAssertEqual(local.viewModel.elements.map(\.itemID), ["killer", "the-killer"])
        XCTAssertTrue(local.viewModel.elements.first?.item === previous.item)
        XCTAssertTrue(local.viewModel.hasLoadedAllPages)
        XCTAssertFalse(local.environment.isHeaderButtonEnabled)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(SearchProtocol.stub.requests.count, 10, "The debounce must not restart an already refined search")

        await model.search(query: "kill")
        XCTAssertEqual(cachedMovieGroup(model)?.viewModel.elements.count, 3, "Backspace can reuse the complete broader snapshot")
        XCTAssertEqual(SearchProtocol.stub.requests.count, 10)
    }

    func testBroaderOrUnrelatedQueriesRequestFreshResults() async {
        let model = model()
        await model.search(query: "kill")
        _ = await model.retrySearch()
        await model.search(query: "ki")
        XCTAssertEqual(model.state, .searching)
        _ = await model.retrySearch()
        XCTAssertEqual(SearchProtocol.stub.requests.count, 20)
        await model.search(query: "alien")
        _ = await model.retrySearch()
        XCTAssertEqual(SearchProtocol.stub.requests.count, 30)
    }

    func testIncompletePagesMustNotBeFilteredLocally() async throws {
        for scenario: SearchProtocol.Scenario in [.many, .duplicates, .shortIncomplete, .unknownTotalTwenty, .partialFailure] {
            let model = model(scenario: scenario)
            await model.search(query: "kill")
            _ = await model.retrySearch()
            if scenario != .partialFailure {
                XCTAssertFalse(try XCTUnwrap(movieGroup(model)).viewModel.hasLoadedAllPages)
            }
            await model.search(query: "killer")
            XCTAssertEqual(model.state, .searching)
            _ = await model.retrySearch()
            XCTAssertEqual(SearchProtocol.stub.requests.count, 20)
        }
    }

    func testCompletenessUsesTheServerTotalAndAllLoadedPages() async throws {
        let model = model(scenario: .many)
        await model.search(query: "kill")
        _ = await model.retrySearch()
        let movies = try XCTUnwrap(movieGroup(model))
        XCTAssertEqual(movies.viewModel.elements.count, 20)
        await movies.viewModel.getNextPage()
        XCTAssertEqual(movies.viewModel.elements.count, 25)
        XCTAssertTrue(movies.viewModel.hasLoadedAllPages)
        await model.search(query: "killer")
        XCTAssertEqual(cachedMovieGroup(model)?.viewModel.elements.count, 25)
        XCTAssertEqual(SearchProtocol.stub.requests.count, 11)
    }

    func testZeroMatchesAreACompleteReusableResult() async throws {
        let model = model()
        await model.search(query: "nothing")
        _ = await model.retrySearch()
        await model.search(query: "nothing more")
        XCTAssertEqual(model.state, .initial)
        XCTAssertTrue(model.isEmpty)
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(SearchProtocol.stub.requests.count, 10)
    }

    func testSearchHeadingsAreLabelsForEveryServerCategory() async throws {
        let provider = SearchContentGroupProvider(userSession: nil)
        let groups = try await provider.makeGroups(environment: .init(filters: .init(query: "kill")))
        XCTAssertEqual(groups.count, 10)
        for group in groups {
            if let group = group as? PosterGroup<ItemLibrary> {
                XCTAssertFalse(group.environment.isHeaderButtonEnabled)
            } else if let group = group as? PosterGroup<PeopleLibrary> {
                XCTAssertFalse(group.environment.isHeaderButtonEnabled)
            } else {
                XCTFail("Unexpected category")
            }
        }
    }

    func testLocalMatchingCoversOriginalTitlesAccentsCaseAndSubstringExtensions() throws {
        let session = session()
        let cache = SearchResultCache()
        let items = try [
            entry("Café Killer", id: "cafe", session: session),
            entry("Translated title", id: "original", original: "Cafe Killer", session: session)
        ]
        cache.store(query: "cafe", rows: [row(items)], session: session)
        XCTAssertEqual(cache.refinedRows(query: "CAFE KILLER", session: session)?.first?.items.count, 2)
        XCTAssertEqual(cache.refinedRows(query: "the cafe killer", session: session)?.first?.items.count, 0)
        XCTAssertNil(cache.refinedRows(query: "caf", session: session))
        XCTAssertNil(cache.refinedRows(query: "cafe%", session: session))
        XCTAssertNil(cache.refinedRows(query: "", session: session))
    }

    func testRemovingAnAccentDoesNotReuseAnOriginalTitleSubsetThatMightBeIncomplete() throws {
        let session = session()
        let cache = SearchResultCache()
        try cache.store(query: "kíll", rows: [row([entry("Killer", id: "one", session: session)])], session: session)
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
    }

    func testCacheIsScopedToTheSessionAndExpires() throws {
        let first = session()
        let second = session()
        var time = Date()
        let cache = SearchResultCache(lifetime: 10, now: { time })
        try cache.store(query: "kill", rows: [row([entry("Killer", id: "one", session: first)])], session: first)
        XCTAssertNotNil(cache.refinedRows(query: "killer", session: first))
        time.addTimeInterval(11)
        XCTAssertNil(cache.refinedRows(query: "killer", session: first))
        cache.store(query: "kill", rows: [row([])], session: first)
        XCTAssertNil(cache.refinedRows(query: "killer", session: second))
    }

    func testLibraryChangesAndDeletedItemsInvalidateCache() throws {
        let session = session()
        let cache = SearchResultCache()
        let item = try entry("Killer", id: "one", session: session)
        cache.store(query: "kill", rows: [row([item])], session: session)
        session.items.libraryDidChange()
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
        cache.store(query: "kill", rows: [row([item])], session: session)
        session.items.delete(id: "one")
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
    }

    func testPageShorterThanLimitWithoutATotalCanBeRefined() async {
        let model = model(scenario: .unknownTotalShort)
        await model.search(query: "kill")
        _ = await model.retrySearch()
        await model.search(query: "killer")
        XCTAssertEqual(model.state, .initial)
        XCTAssertEqual(cachedMovieGroup(model)?.viewModel.elements.count, 2)
        XCTAssertEqual(SearchProtocol.stub.requests.count, 10)
    }

    func testChangedLibraryDoesNotRecachePreviouslyDisplayedResults() async {
        let model = model()
        await model.search(query: "kill")
        _ = await model.retrySearch()
        model.userSession?.items.libraryDidChange()
        await model.search(query: "killer")
        XCTAssertEqual(model.state, .searching)
        _ = await model.retrySearch()
        XCTAssertEqual(SearchProtocol.stub.requests.count, 20)
    }

    func testSameQueryReloadsAutomaticallyAfterCacheInvalidation() async throws {
        let model = model()
        await model.search(query: "kill")
        _ = await model.retrySearch()
        model.userSession?.items.libraryDidChange()
        await model.search(query: "KILL")
        try await Task.sleep(for: .milliseconds(750))
        XCTAssertEqual(model.state, .initial)
        XCTAssertEqual(SearchProtocol.stub.requests.count, 20)
        XCTAssertEqual(movieGroup(model)?.viewModel.elements.count, 3)
    }

    func testCancelledOlderSearchCannotReplaceTheLatestResults() async throws {
        let model = model(scenario: .delayed)
        await model.search(query: "kill")
        let oldRequest = Task { await model.retrySearch() }
        for _ in 0 ..< 30 where SearchProtocol.stub.requests.count < 10 {
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.search(query: "killer")
        let failure = await model.retrySearch()
        XCTAssertNil(failure)
        _ = await oldRequest.value
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(model.state, .initial)
        let visibleItems = movieGroup(model)?.viewModel.elements.map(\.itemID) ??
            cachedMovieGroup(model)?.viewModel.elements.map(\.itemID)
        XCTAssertEqual(visibleItems, ["killer", "the-killer"])
        XCTAssertEqual(model.filterViewModel.currentFilters.query, "killer")
    }

    func testWatchedStateStaysLiveAndTitleChangesInvalidateTheSnapshot() throws {
        let session = session()
        let cache = SearchResultCache()
        let item = try entry("Killer", id: "one", session: session)
        cache.store(query: "kill", rows: [row([item])], session: session)
        item.item.beginChange(id: UUID(), field: \.isPlayed, value: true)
        XCTAssertEqual(cache.refinedRows(query: "killer", session: session)?.first?.items.first?.snapshot.userData?.isPlayed, true)
        let token = try session.items.beginRequest()
        _ = try session.items.merge(ItemPatch.snapshot(BaseItemDto(id: "one", name: "Alien", type: .movie)), token: token)
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
    }

    func testCustomSortTitleAndNonSubstringProviderMatchesUseTheServer() throws {
        let session = session()
        let cache = SearchResultCache()
        var value = BaseItemDto(id: "one", name: "Kill Bill", sortName: "Killer", type: .movie)
        let item = try ItemEntry(item: session.items.record(for: value))
        cache.store(query: "kill", rows: [row([item])], session: session)
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
        value.id = "fuzzy"
        value.name = "Different title"
        value.sortName = nil
        try cache.store(query: "kill", rows: [row([ItemEntry(item: session.items.record(for: value))])], session: session)
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
    }

    func testChangedEndpointAndEndedSessionCannotReuseCachedRows() throws {
        let session = session()
        let cache = SearchResultCache()
        cache.store(query: "kill", rows: [row([])], session: session)
        session.client = try JellyfinClient(configuration: .alphaneConfiguration(
            url: XCTUnwrap(URL(string: "https://other.example")),
            accessToken: "test-token"
        ))
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
        cache.store(query: "kill", rows: [row([])], session: session)
        session.items.invalidate()
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
    }

    func testRepeatedRefinementDoesNotExtendTheLifetimeOfAnOldServerResult() throws {
        let session = session()
        var time = Date()
        let sourceTime = time
        let cache = SearchResultCache(lifetime: 10, now: { time })
        let rows = try [row([entry("Killer", id: "one", session: session)])]
        cache.store(query: "kill", rows: rows, session: session, recordedAt: sourceTime)
        time.addTimeInterval(9)
        cache.store(query: "killer", rows: rows, session: session, recordedAt: sourceTime)
        time.addTimeInterval(2)
        XCTAssertNil(cache.refinedRows(query: "killer", session: session))
    }

    private func model(scenario: SearchProtocol.Scenario = .normal) -> SearchViewModel {
        SearchProtocol.stub.reset(scenario: scenario)
        let session = session()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SearchProtocol.self]
        session.client = JellyfinClient(
            configuration: .alphaneConfiguration(
                url: session.server.effectiveServerURL,
                accessToken: "test-token"
            ),
            sessionConfiguration: configuration
        )
        let model = SearchViewModel()
        model.userSession = session
        return model
    }

    private func session() -> UserSession {
        let url = URL(string: "https://search.example")!
        let session = UserSession(
            server: ServerState(urls: [url], currentURL: url, name: "Test", id: "server", userIDs: ["user"]),
            user: UserState(id: "user", serverID: "server", username: "User")
        )
        session.client = JellyfinClient(configuration: .alphaneConfiguration(url: url, accessToken: "test-token"))
        return session
    }

    private func movieGroup(_ model: SearchViewModel) -> PosterGroup<ItemLibrary>? {
        model.itemContentGroupViewModel
            .groups
            .compactMap { $0 as? PosterGroup<ItemLibrary> }
            .first { $0.id == "unknown-Movie" }
    }

    private func cachedMovieGroup(_ model: SearchViewModel) -> PosterGroup<StaticLibrary<ItemEntry>>? {
        model.itemContentGroupViewModel
            .groups
            .compactMap { $0 as? PosterGroup<StaticLibrary<ItemEntry>> }
            .first { $0.id == "unknown-Movie" }
    }

    private func entry(_ name: String, id: String, original: String? = nil, session: UserSession) throws -> ItemEntry {
        var value = BaseItemDto()
        value.id = id
        value.name = name
        value.originalTitle = original
        value.type = .movie
        return try ItemEntry(item: session.items.record(for: value))
    }

    private func row(_ items: [ItemEntry]) -> SearchResultCache.Row {
        .init(id: "movies", title: "Movies", displayType: .portrait, items: items)
    }
}

private final class SearchProtocol: URLProtocol, @unchecked Sendable {
    enum Scenario { case normal, many, duplicates, shortIncomplete, unknownTotalTwenty, unknownTotalShort, partialFailure, delayed }
    private let deliveryLock = NSLock()
    private var stopped = false
    static let stub = Stub()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {
        deliveryLock.lock()
        stopped = true
        deliveryLock.unlock()
    }

    override func startLoading() {
        let data = Self.stub.response(to: request)
        if Self.stub.shouldDelay(request) {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.deliver(data) }
        } else {
            deliver(data)
        }
    }

    private func deliver(_ data: Data) {
        deliveryLock.lock()
        let stopped = stopped
        deliveryLock.unlock()
        guard !stopped else { return }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    final class Stub: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [URLRequest] = []
        private var scenario: Scenario = .normal

        var requests: [URLRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func reset(scenario: Scenario) {
            lock.lock()
            defer { lock.unlock() }
            recorded = []
            self.scenario = scenario
        }

        func shouldDelay(_ request: URLRequest) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let parameters = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            return scenario == .delayed && parameters.contains { $0.name.lowercased() == "searchterm" && $0.value == "kill" }
        }

        func response(to request: URLRequest) -> Data {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(request)
            let parameters = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func parameter(_ name: String) -> String {
                parameters.first { $0.name.lowercased() == name.lowercased() }?.value ?? ""
            }
            var items: [[String: Any]] = []
            if scenario == .partialFailure, request.url?.path.lowercased().hasSuffix("/persons") == true {
                return Data("unreadable response".utf8)
            }
            var total: Any = 0
            if parameter("includeItemTypes").contains("Movie") {
                switch scenario {
                case .normal, .delayed, .partialFailure, .unknownTotalShort:
                    items = [("bill", "Kill Bill"), ("killer", "Killer"), ("the-killer", "The Killer")]
                        .filter { $0.1.lowercased().contains(parameter("searchTerm").lowercased()) }
                        .map { ["Id": $0.0, "Name": $0.1, "Type": "Movie", "SortName": $0.1.lowercased()] }
                    total = scenario == .unknownTotalShort ? NSNull() : items.count

                case .many, .unknownTotalTwenty:
                    let offset = Int(parameter("startIndex")) ?? 0
                    items = (offset ..< min(offset + 20, 25)).map {
                        ["Id": "movie-\($0)", "Name": "Killer \($0)", "Type": "Movie"]
                    }
                    total = scenario == .unknownTotalTwenty ? NSNull() : 25

                case .duplicates:
                    items = Array(repeating: ["Id": "one", "Name": "Killer", "Type": "Movie"], count: 20)
                    total = 30

                case .shortIncomplete:
                    items = [["Id": "one", "Name": "Killer", "Type": "Movie"]]
                    total = 30
                }
            }
            return try! JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": total])
        }
    }
}
