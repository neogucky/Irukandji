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
            case let .search(query):
                query.nilIfBlank == nil ? .to(.initial) : .to(.searching)
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

    let itemContentGroupViewModel: ContentGroupViewModel<SearchContentGroupProvider>

    var filterViewModel: FilterViewModel {
        itemContentGroupViewModel.provider.filterViewModel
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
        self.itemContentGroupViewModel = .init(provider: .init())

        super.init()

        itemContentGroupViewModel.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        observeFilters()
    }

    private func observeFilters() {
        filterViewModel.$currentFilters
            .debounce(for: 0.5, scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?._actuallySearch()
            }
            .store(in: &cancellables)
    }

    func retrySearch() async -> Error? {
        error = nil
        await _actuallySearch()
        return state == .error ? error ?? ErrorMessage(L10n.unknownError) : nil
    }

    @Function(\Action.Cases.search)
    private func _search(_ query: String) async throws {
        filterViewModel.currentFilters = .init(query: query.nilIfBlank)

        await cancel()
    }

    @Function(\Action.Cases._actuallySearch)
    private func __actuallySearch() async throws {

        guard canSearch else { return }

        let filters = filterViewModel.currentFilters

        itemContentGroupViewModel.provider.environment.filters = filters

        await itemContentGroupViewModel.refresh()
        try Task.checkCancellation()
        if let failure = itemContentGroupViewModel.provider.resultError {
            throw failure
        }
    }
}
