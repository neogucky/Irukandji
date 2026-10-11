//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension ItemView {
    /// Secondary browsing links share one compact area below the cinematic hero.
    struct TVDetailMetadataContentGroup: ContentGroup {
        let id = "item-metadata"
        let item: BaseItemDto

        var _shouldBeResolved: Bool {
            item.itemGenres?.isNotEmpty == true || item.studios?.isNotEmpty == true
        }

        func body(with viewModel: Empty) -> some View {
            VStack(alignment: .leading, spacing: 12) {
                if let genres = item.itemGenres, genres.isNotEmpty {
                    PillGroup(
                        displayTitle: L10n.genres,
                        id: "genres",
                        elements: genres,
                        presentation: .inline
                    ) { router, genre in
                        router.route(to: .contentGroup(provider: ItemTypeContentGroupProvider(
                            itemTypes: browseItemTypes,
                            parent: BaseItemDto(name: genre.displayTitle),
                            environment: .init(filters: .init(genres: [genre]))
                        )))
                    }
                    .body(with: .init())
                }

                if let studios = item.studios, studios.isNotEmpty {
                    PillGroup(
                        displayTitle: L10n.studios,
                        id: "studios",
                        elements: studios,
                        presentation: .inline
                    ) { router, studio in
                        router.route(to: .contentGroup(provider: ItemTypeContentGroupProvider(
                            itemTypes: browseItemTypes,
                            parent: BaseItemDto(id: studio.id, name: studio.displayTitle, type: .studio)
                        )))
                    }
                    .body(with: .init())
                }
            }
        }

        private var browseItemTypes: [BaseItemKind] {
            [.movie, .series, .boxSet, .episode, .musicVideo, .video, .liveTvProgram, .tvChannel, .person]
        }
    }
}
