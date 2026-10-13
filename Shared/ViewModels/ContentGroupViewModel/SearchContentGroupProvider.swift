//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import Foundation
import JellyfinAPI

@MainActor
struct SearchContentGroupProvider: ContentGroupProvider {

    struct Environment: WithDefaultValue {
        var filters: ItemFilterCollection

        static var `default`: Self {
            .init(filters: .init())
        }
    }

    let id: String = UUID().uuidString
    let displayTitle: String = L10n.search
    let filterViewModel: FilterViewModel
    var environment: Environment
    private let results = Results()
    let cache: SearchResultCache
    var userSession: UserSession?

    private static let itemTypes: [BaseItemKind] = [
        .movie, .series, .boxSet, .episode, .musicVideo, .video,
        .liveTvProgram, .tvChannel, .musicArtist
    ]

    /// Empty successful rows mean no matches. If every row failed, present the
    /// request error instead of claiming there are no matching titles.
    var resultError: Error? {
        var failures: [Error] = []
        for group in results.groups {
            if let group = group as? PosterGroup<ItemLibrary>, group.viewModel.state == .error {
                failures.append(group.viewModel.error ?? ErrorMessage(L10n.unknownError))
            } else if let group = group as? PosterGroup<PeopleLibrary>, group.viewModel.state == .error {
                failures.append(group.viewModel.error ?? ErrorMessage(L10n.unknownError))
            } else if let group = group as? PosterGroup<StaticLibrary<ItemEntry>>, group.viewModel.state == .error {
                failures.append(group.viewModel.error ?? ErrorMessage(L10n.unknownError))
            } else {
                return nil
            }
        }
        return failures.first
    }

    private final class Results {
        var groups: [any ContentGroup] = []
        var query: String?
        weak var session: UserSession?
        var serverURL: URL?
        var cacheRevision: UInt = 0
        var loadedAt = Date()
    }

    init(
        userSession: UserSession? = Container.shared.currentUserSession(),
        cache: SearchResultCache? = nil,
        filterViewModel: FilterViewModel? = nil
    ) {
        self.userSession = userSession
        self.cache = cache ?? SearchResultCache()
        let filterViewModel = filterViewModel ?? FilterViewModel()

        self.filterViewModel = filterViewModel
        self.environment = .init(filters: filterViewModel.currentFilters)
    }

    func cancelPendingLoads() async {
        for group in results.groups {
            if let group = group as? PosterGroup<ItemLibrary> {
                await group.viewModel.cancelPendingLoads()
            } else if let group = group as? PosterGroup<PeopleLibrary> {
                await group.viewModel.cancelPendingLoads()
            }
        }
    }

    func makeGroups(environment: Environment) async throws -> [any ContentGroup] {
        if let userSession {
            cache.prepare(session: userSession)
        }
        let itemGroups: [any ContentGroup] = Self.itemTypes.map { type in
            var filters = environment.filters
            filters.itemTypes = type == .boxSet ? [.boxSet, .userView] : [type]
            let library = ItemLibrary(
                parent: BaseItemDto(),
                filters: filters,
                additionalItemFields: [.originalTitle, .sortName]
            )
            return PosterGroup(
                id: "unknown-\(type.rawValue)",
                library: library,
                displayTitle: type.pluralDisplayTitle,
                posterDisplayType: type.preferredPosterDisplayType,
                environment: .init(isHeaderButtonEnabled: false),
                viewModel: PagingLibraryViewModel(library: library, pageSize: 20, userSession: userSession)
            )
        }

        let library = PeopleLibrary(environment: .init(query: environment.filters.query))
        let people = PosterGroup(
            id: "search-people",
            library: library,
            environment: .init(isHeaderButtonEnabled: false),
            viewModel: PagingLibraryViewModel(library: library, pageSize: 20, userSession: userSession)
        )
        results.groups = itemGroups + [people]
        results.query = environment.filters.query
        results.session = userSession
        results.serverURL = userSession?.client.configuration.url
        results.cacheRevision = cache.revision
        results.loadedAt = Date()
        return results.groups
    }

    func captureCompleteResults() {
        guard let query = results.query, let userSession, results.groups.isNotEmpty,
              results.session === userSession, results.serverURL == userSession.client.configuration.url,
              results.cacheRevision == cache.revision else { return }

        var rows: [SearchResultCache.Row] = []
        for group in results.groups {
            if let group = group as? PosterGroup<ItemLibrary>, group.viewModel.hasLoadedAllPages {
                rows.append(.init(
                    id: group.id,
                    title: group.displayTitle,
                    displayType: group.posterDisplayType,
                    items: group.viewModel.elements.elements
                ))
            } else if let group = group as? PosterGroup<PeopleLibrary>, group.viewModel.hasLoadedAllPages {
                rows.append(.init(
                    id: group.id,
                    title: group.displayTitle,
                    displayType: group.posterDisplayType,
                    items: group.viewModel.elements.elements
                ))
            } else if let group = group as? PosterGroup<StaticLibrary<ItemEntry>>, group.viewModel.hasLoadedAllPages {
                rows.append(.init(
                    id: group.id,
                    title: group.displayTitle,
                    displayType: group.posterDisplayType,
                    items: group.viewModel.elements.elements
                ))
            } else {
                // One failed or unfinished category makes the overall result incomplete.
                return
            }
        }
        cache.store(query: query, rows: rows, session: userSession, recordedAt: results.loadedAt)
    }

    func cachedGroups(query: String) -> [any ContentGroup]? {
        guard let userSession, let rows = cache.refinedRows(query: query, session: userSession) else { return nil }

        let groups: [any ContentGroup] = rows.map { row in
            let library = StaticLibrary(title: row.title, id: row.id, elements: row.items)
            let model = PagingLibraryViewModel(library: library, pageSize: 20, userSession: userSession)
            model.installCompleteResults(row.items)
            return PosterGroup(
                id: row.id,
                library: library,
                displayTitle: row.title,
                posterDisplayType: row.displayType,
                environment: .init(isHeaderButtonEnabled: false),
                viewModel: model
            )
        }
        results.groups = groups
        results.query = query
        results.session = userSession
        results.serverURL = userSession.client.configuration.url
        results.cacheRevision = cache.revision
        results.loadedAt = cache.lastRefinementDate ?? Date()
        return groups
    }
}
