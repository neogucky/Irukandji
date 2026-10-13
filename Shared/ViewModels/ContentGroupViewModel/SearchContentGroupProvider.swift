//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

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

    /// Empty successful rows mean no matches. If every row failed, present the
    /// request error instead of claiming there are no matching titles.
    var resultError: Error? {
        var failures: [Error] = []
        for group in results.groups {
            if let group = group as? PosterGroup<ItemLibrary>, group.viewModel.state == .error {
                failures.append(group.viewModel.error ?? ErrorMessage(L10n.unknownError))
            } else if let group = group as? PosterGroup<PeopleLibrary>, group.viewModel.state == .error {
                failures.append(group.viewModel.error ?? ErrorMessage(L10n.unknownError))
            } else {
                return nil
            }
        }
        return failures.first
    }

    private final class Results {
        var groups: [any ContentGroup] = []
    }

    init() {
        let filterViewModel: FilterViewModel = .init()

        self.filterViewModel = filterViewModel
        self.environment = .init(filters: filterViewModel.currentFilters)
    }

    func makeGroups(environment: Environment) async throws -> [any ContentGroup] {
        let itemGroups = try await ItemTypeContentGroupProvider(
            itemTypes: [
                BaseItemKind.movie,
                .series,
                .boxSet,
                .episode,
                .musicVideo,
                .video,
                .liveTvProgram,
                .tvChannel,
                .musicArtist,
            ]
        )
        .makeGroups(environment: .init(filters: environment.filters))

        let people = PosterGroup(
            library: PeopleLibrary(
                environment: .init(query: environment.filters.query)
            )
        )
        results.groups = itemGroups + [people]
        return results.groups
    }
}
