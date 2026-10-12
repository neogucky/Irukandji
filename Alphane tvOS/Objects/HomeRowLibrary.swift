//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// Start prefetch as fixed rows enter the viewport, before Down reaches their end.
/// Visibility observation does not change scroll or focus geometry.
struct HomePrefetchRow<Library: PagingLibrary>: ContentGroup
where Library.Element: LibraryElement, Library.Element: Poster {
    let group: PosterGroup<Library>
    let discovery: HomeDiscoveryViewModel
    var id: String {
        group.id
    }

    var viewModel: PagingLibraryViewModel<Library> {
        group.viewModel
    }

    var _shouldBeResolved: Bool {
        group._shouldBeResolved
    }

    func body(with viewModel: PagingLibraryViewModel<Library>) -> some View {
        group.body(with: viewModel)
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                if visible, discovery.rows.isEmpty {
                    Task { await discovery.loadMore() }
                }
            }
    }
}

struct HomeRowLibrary: PagingLibrary {
    let row: HomeDiscoveryRow
    let libraries: [BaseItemDto]
    var parent: TitledLibraryParent {
        .init(displayTitle: row.title, id: row.id)
    }

    let hasNextPage = false

    func retrievePage(environment: Empty, pageState: LibraryPageState) async throws -> [BaseItemDto] {
        if let itemID = row.similarItemID {
            var parameters = Paths.GetSimilarItemsParameters()
            parameters.userID = pageState.userSession.user.id
            parameters.fields = PosterSubtitleField.itemFields
            parameters.limit = pageState.pageSize + 6
            let response = try await pageState.userSession.client.send(Paths.getSimilarItems(itemID: itemID, parameters: parameters))
            return Array(row.normalized(response.value.items ?? []).prefix(pageState.pageSize))
        }

        // Query each configured library, then merge globally. An empty list never
        // falls back to querying every library, including ones excluded from Home.
        let collectionType: CollectionType = row.itemType == .movie ? .movies : .tvshows
        let roots = libraries.filter { $0.collectionType == collectionType }.compactMap(\.id)
        var items: [BaseItemDto] = []
        for id in roots {
            let parameters = row.parameters(userID: pageState.userSession.user.id, parentID: id, limit: pageState.pageSize)
            let response = try await pageState.userSession.client.send(Paths.getItems(parameters: parameters))
            items += response.value.items ?? []
        }
        items = row.normalized(items)
        switch row.sort {
        case .random:
            items.shuffle()
        case .newest:
            items.sort { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        case .rating:
            items.sort { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        }
        return Array(items.prefix(pageState.pageSize))
    }
}

@MainActor
enum TVHomeRows {
    static let fixedIDs = ["cinematic-selection", "home-next-up", HomeDiscoveryRow.newMovies.id, HomeDiscoveryRow.newShows.id]

    static func makeGroups(userSession: UserSession, libraries: [BaseItemDto]) -> [any ContentGroup] {
        let discovery = HomeDiscoveryContentGroup(userSession: userSession, libraries: libraries)
        let rowEnvironment = PosterGroup<HomeRowLibrary>.Environment(
            isHeaderButtonEnabled: false,
            minimumItemCount: HomeDiscoveryRow.minimumItemCount
        )
        return [
            CinematicSelectionContentGroup(
                resumeLibrary: ResumeItemsLibrary(mediaTypes: [.video]),
                recentlyAddedLibrary: RecentlyAddedLibrary(),
                includesRecentlyAdded: false
            ),
            HomePrefetchRow(
                group: PosterGroup(id: fixedIDs[1], library: NextUpLibrary(), environment: .init(isHeaderButtonEnabled: false)),
                discovery: discovery.viewModel
            ),
            HomePrefetchRow(group: PosterGroup(
                id: fixedIDs[2],
                library: HomeRowLibrary(row: .newMovies, libraries: libraries),
                posterDisplayType: .landscape,
                environment: rowEnvironment
            ), discovery: discovery.viewModel),
            HomePrefetchRow(group: PosterGroup(
                id: fixedIDs[3],
                library: HomeRowLibrary(row: .newShows, libraries: libraries),
                posterDisplayType: .landscape,
                environment: rowEnvironment
            ), discovery: discovery.viewModel),
            discovery
        ]
    }
}
