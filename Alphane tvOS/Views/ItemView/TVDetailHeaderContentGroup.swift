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

    struct TVDetailHeaderContentGroup: ContentGroup {

        let id = ItemView.Component.header
        let provider: ItemContentGroupProvider

        func body(with viewModel: Empty) -> Body {
            Body(provider: provider)
        }

        struct Body: View {

            @Router
            private var router

            @Environment(\.frameForParentView)
            private var frameForParentView

            @FocusState
            private var focusedDetail: String?

            @ObservedObject
            var provider: ItemContentGroupProvider
            var viewportHeightOverride: CGFloat? = nil
            var showsArtwork = true
            var bottomPadding: CGFloat = 72

            private var descriptionIsFocused: Bool {
                focusedDetail == ItemView.Component.description
            }

            @StoredValue(.User.itemViewAttributes)
            private var attributes

            private var overviewText: String? {
                let text = provider.item.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
                return text?.isEmpty == false ? text : nil
            }

            private var viewportHeight: CGFloat {
                if let viewportHeightOverride { return viewportHeightOverride }
                let height = frameForParentView[.scrollView, default: .zero].frame.height
                return height > 0 ? height : 1080
            }

            private var usesPanorama: Bool {
                provider.item.type != .person && provider.item.type != .season
            }

            private var posterDisplayType: PosterDisplayType {
                provider.item.type == .person ? .portrait : .landscape
            }

            private var title: some View {
                VStack(alignment: .leading, spacing: 14) {
                    if let parentID = provider.item.parentRootID, let parentTitle = provider.item.parentTitle {
                        ParentButton(title: parentTitle, id: parentID)
                            .font(.system(size: 22, weight: .medium))
                            .coordinatedFocus(ItemView.Component.parent, selection: $focusedDetail)
                    }

                    Text(provider.item.displayTitle)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    MetadataHStack(item: provider.item)
                        .font(.system(size: 22))
                        .foregroundStyle(AlphaneTheme.secondaryText)
                }
            }

            @ViewBuilder
            private var overview: some View {
                if let overviewText {
                    Button {
                        router.route(to: .itemOverview(item: provider.item))
                    } label: {
                        SeeMoreText(overviewText)
                            .font(.system(size: 24))
                            .foregroundStyle(descriptionIsFocused ? .white : AlphaneTheme.secondaryText)
                            .lineSpacing(5)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.focusBorder)
                    .coordinatedFocus(ItemView.Component.description, selection: $focusedDetail)
                    .frame(maxWidth: 1040, alignment: .leading)
                    .accessibilityIdentifier("item-description")
                }
            }

            @ViewBuilder
            private var seasonsButton: some View {
                if !provider.episodeSeasons.isEmpty {
                    Menu {
                        ForEach(provider.episodeSeasons, id: \.id) { season in
                            Button(season.displayTitle) {
                                router.route(to: .item(item: season))
                            }
                        }
                    } label: {
                        Label(L10n.seasons, systemImage: "chevron.down")
                            .labelStyle(.trailingIcon)
                    }
                    .buttonStyle(.capsule)
                    .controlSize(.large)
                    .coordinatedFocus(ItemView.Component.seasons, selection: $focusedDetail)
                    .accessibilityIdentifier("item-seasons")
                }
            }

            private var panoramaActions: some View {
                HStack(spacing: 28) {
                    ActionBar(provider: provider, alignment: .leading)

                    if !provider.episodeSeasons.isEmpty {
                        Rectangle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 1, height: 28)
                            .accessibilityHidden(true)

                        seasonsButton
                    }
                }
                .padding(.top, 12)
                .focusSection()
            }

            private var panoramaDetails: some View {
                VStack(alignment: .leading, spacing: 14) {
                    title

                    overview

                    AttributesHStack(
                        attributes: attributes,
                        item: provider.item,
                        selectedMediaSource: provider.mediaPlayerItemProvider?.mediaSource,
                        alignment: .leading
                    )
                    .font(.system(size: 18))
                    .foregroundStyle(AlphaneTheme.secondaryText)

                    panoramaActions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            private var panorama: some View {
                HStack(alignment: .bottom, spacing: 72) {
                    panoramaDetails

                    if provider.item.userData?.isPlayed == true,
                       let next = provider.nextEpisodeItemProvider?.item
                    {
                        NextEpisodeCard(item: next) {
                            router.route(to: .item(item: next, startPlayback: true))
                        }
                    }
                }
                .edgePadding(.horizontal)
                .padding(.top, viewportHeight * 0.34)
                .padding(.bottom, bottomPadding)
                .frame(minHeight: viewportHeight, alignment: .bottom)
                .background {
                    if showsArtwork {
                        TVDetailArtwork(provider: provider, isShowingInfo: false)
                    }
                }
                .accessibilityElement(children: .contain)
            }

            @ViewBuilder
            private var compactOverview: some View {
                if let overviewText {
                    Text(overviewText)
                        .font(.system(size: 24))
                        .foregroundStyle(AlphaneTheme.secondaryText)
                        .lineSpacing(5)
                        .lineLimit(3)
                }
            }

            private var compactHeader: some View {
                ImageContentColumnsLayout(
                    idealContentWidth: 760,
                    imageAspectRatio: posterDisplayType == .landscape ? 16.0 / 9.0 : 2.0 / 3.0,
                    imageColumnFraction: posterDisplayType == .landscape ? 0.44 : 0.28,
                    spacing: 64,
                    centersContent: true
                ) {
                    PosterImage(item: provider.item, type: posterDisplayType, size: .medium, contentMode: .fill)
                        .posterCornerRadius(posterDisplayType)
                        .subtleShadow()
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 24) {
                        title
                        compactOverview
                        AttributesHStack(
                            attributes: attributes,
                            item: provider.item,
                            selectedMediaSource: provider.mediaPlayerItemProvider?.mediaSource,
                            alignment: .leading
                        )
                        .foregroundStyle(AlphaneTheme.secondaryText)
                        .font(.system(size: 18))

                        ActionBar(provider: provider, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .edgePadding(.horizontal)
                .padding(.top, 72)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .focusSection()
            }

            var body: some View {
                if usesPanorama {
                    panorama
                } else {
                    compactHeader
                }
            }
        }
    }

    private struct NextEpisodeCard: View {

        @Environment(\.initialFocusSelection)
        private var initialFocusSelection

        @FocusState
        private var localFocusSelection: String?

        private var focusSelection: FocusState<String?>.Binding {
            initialFocusSelection ?? $localFocusSelection
        }

        private var isFocused: Bool {
            focusSelection.wrappedValue == ItemView.Component.nextEpisode
        }

        let item: BaseItemDto
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.next)
                        .font(.system(size: 24, weight: .medium))

                    ImageView(item.imageSources(
                        for: .landscape,
                        environment: .init(maxWidth: 640, useParent: false, viewContext: [.isThumb])
                    ))
                    .image { (image: Image) in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 360, height: 202.5)
                    }
                    .failure {
                        AlphaneTheme.background
                            .overlay { Image(systemName: "film") }
                    }
                    .frame(width: 360, height: 202.5)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .tvFocusBorder(isFocused: isFocused, shape: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.displayTitle)
                            .font(.system(size: 26, weight: .medium))
                            .lineLimit(2)

                        DotHStack {
                            if let locator = item.seasonEpisodeLabel {
                                Text(locator)
                            }
                            if let runtime = item.runtime {
                                Text(runtime, format: .hourMinuteAbbreviated)
                            }
                        }
                        .font(.system(size: 20))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(isFocused ? .white : AlphaneTheme.secondaryText)
                .multilineTextAlignment(.leading)
                .frame(width: 360)
            }
            .buttonStyle(ArtworkButtonStyle())
            .coordinatedFocus(ItemView.Component.nextEpisode, selection: focusSelection)
            .accessibilityIdentifier("item-next-episode")
        }
    }
}
