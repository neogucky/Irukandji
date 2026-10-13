//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import SwiftUI

@MainActor
@Stateful
final class SearchViewModel: ViewModel {

    @CasePathable
    enum Action {

        case search(query: String)
        case _actuallySearch

        var transition: Transition {
            switch self {
            case .search:
                .none
            case ._actuallySearch:
                .to(.searching, then: .initial)
                    .onRepeat(.cancel)
            }
        }
    }

    enum State {

        case error
        case initial
        case searching
    }

    @Published
    private(set) var itemContentGroupViewModel: ContentGroupViewModel<SearchContentGroupProvider>

    private var lastPresentedQuery: String?
    private let queryFilters = FilterViewModel()
    private let resultCache = SearchResultCache()
    private var contentChanges: AnyCancellable?
    private var pendingContent: ContentGroupViewModel<SearchContentGroupProvider>?

    var filterViewModel: FilterViewModel {
        queryFilters
    }

    var isEmpty: Bool {
        itemContentGroupViewModel.groups.isEmpty
    }

    var isNotEmpty: Bool {
        !isEmpty
    }

    var canSearch: Bool {
        filterViewModel.currentFilters.query?.nilIfBlank != nil
    }

    override init() {
        self.itemContentGroupViewModel = .init(provider: .init(cache: resultCache, filterViewModel: queryFilters))

        super.init()

        observeContent()
        observeFilters()
    }

    private func observeContent() {
        contentChanges = itemContentGroupViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private func observeFilters() {
        filterViewModel.$currentFilters
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.canSearch,
                      SearchResultCache.normalizedQuery(self.filterViewModel.currentFilters.query ?? "") != self.lastPresentedQuery
                else { return }

                self._actuallySearch()
            }
            .store(in: &cancellables)
    }

    func retrySearch() async -> Error? {
        error = nil
        lastPresentedQuery = nil
        await _actuallySearch()
        return state == .error ? error ?? ErrorMessage(L10n.unknownError) : nil
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        itemContentGroupViewModel.provider.userSession = userSession
        itemContentGroupViewModel.provider.captureCompleteResults()
        error = nil
        lastPresentedQuery = nil
        filterViewModel.currentFilters = .init(query: query.nilIfBlank)

        await cancel()
        await pendingContent?.provider.cancelPendingLoads()
        await pendingContent?.cancelPendingRefresh()
        await itemContentGroupViewModel.provider.cancelPendingLoads()
        await itemContentGroupViewModel.cancelPendingRefresh()

        let cachedGroups = itemContentGroupViewModel.provider.cachedGroups(query: query)
        state = query.isEmpty || cachedGroups != nil ? .initial : .searching
        if let cachedGroups {
            await itemContentGroupViewModel.presentCachedGroups(cachedGroups)
            lastPresentedQuery = SearchResultCache.normalizedQuery(query)
        }
    }

    @Function(\Action.Cases._actuallySearch)
    private func __actuallySearch() async throws {

        guard canSearch else { return }

        let filters = filterViewModel.currentFilters

        let session = userSession
        let provider = SearchContentGroupProvider(userSession: session, cache: resultCache, filterViewModel: queryFilters)
        let content = ContentGroupViewModel(provider: provider)
        content.provider.environment.filters = filters
        pendingContent = content

        await content.refresh()
        try Task.checkCancellation()
        guard filters.query == filterViewModel.currentFilters.query, session === userSession else { throw CancellationError() }

        if let failure = content.provider.resultError {
            throw failure
        }
        error = nil
        itemContentGroupViewModel = content
        observeContent()
        content.provider.captureCompleteResults()
        if pendingContent === content {
            pendingContent = nil
        }
        lastPresentedQuery = SearchResultCache.normalizedQuery(filters.query ?? "")
    }
}
