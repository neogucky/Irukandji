//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct EpisodeNavigationContentGroup: ContentGroup {

    let id = "episode-navigation"
    let nextEpisode: BaseItemDto?
    let seasons: [BaseItemDto]

    func body(with viewModel: Empty) -> some View {
        Content(nextEpisode: nextEpisode, seasons: seasons)
    }

    private struct Content: View {

        @Router
        private var router

        @State
        private var contentSize: CGSize = .zero

        let nextEpisode: BaseItemDto?
        let seasons: [BaseItemDto]

        private var posterWidth: CGFloat {
            #if os(tvOS)
            max(140, (contentSize.width - 2 * EdgeInsets.edgePadding - 5 * EdgeInsets.itemSpacing) / 6)
            #else
            UIDevice.isPad ? 140 : max(120, (contentSize.width - 2 * EdgeInsets.edgePadding - EdgeInsets.itemSpacing) / 2)
            #endif
        }

        private var headerSpacing: CGFloat {
            UIDevice.isTV ? 30 : 15
        }

        private var groupSpacing: CGFloat {
            UIDevice.isTV ? 48 : 20
        }

        private func heading(_ title: String) -> some View {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }

        private func poster(for item: BaseItemDto) -> some View {
            PosterButton(item: item, displayType: .portrait, size: .small) { namespace in
                item.libraryDidSelectElement(router: router, in: namespace)
            }
            .frame(width: posterWidth)
        }

        var body: some View {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: groupSpacing) {
                    if let nextEpisode {
                        VStack(alignment: .leading, spacing: headerSpacing) {
                            heading(L10n.next)
                            poster(for: nextEpisode)
                        }
                        .focusSection()
                    }

                    if nextEpisode != nil, !seasons.isEmpty {
                        Rectangle()
                            .fill(.secondary.opacity(0.3))
                            .frame(width: 1, height: posterWidth * 1.5 + headerSpacing + (UIDevice.isTV ? 45 : 25))
                            .accessibilityHidden(true)
                    }

                    if !seasons.isEmpty {
                        VStack(alignment: .leading, spacing: headerSpacing) {
                            heading(L10n.seasons)

                            HStack(alignment: .top, spacing: EdgeInsets.itemSpacing) {
                                ForEach(seasons, id: \.id) { season in
                                    poster(for: season)
                                }
                            }
                            .focusSection()
                        }
                        .focusSection()
                    }
                }
                .edgePadding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .trackingSize($contentSize)
            .withViewContext(.isThumb)
            .focusSection()
            .accessibilityElement(children: .contain)
        }
    }
}
