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
            private var descriptionIsFocused: Bool

            @ObservedObject
            var provider: ItemContentGroupProvider

            @StoredValue(.User.itemViewAttributes)
            private var attributes

            private var overviewText: String? {
                let text = provider.item.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
                return text?.isEmpty == false ? text : nil
            }

            private var viewportHeight: CGFloat {
                let height = frameForParentView[.scrollView, default: .zero].frame.height
                return height > 0 ? height : 1080
            }

            private var artworkHeight: CGFloat {
                // Use the space for artwork when there is no synopsis, rather than
                // leaving a blank description area. Text below remains self-sizing.
                let fraction = provider.item.type == .episode
                    ? (overviewText == nil ? 0.54 : 0.46)
                    : 0.58
                return max(360, viewportHeight * fraction)
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
                    }

                    Text(provider.item.displayTitle)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    MetadataHStack(item: provider.item)
                        .font(.system(size: 22))
                        .foregroundStyle(IrukandjiTheme.secondaryText)
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
                            .foregroundStyle(descriptionIsFocused ? .white : IrukandjiTheme.secondaryText)
                            .lineSpacing(5)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.focusBorder)
                    .focused($descriptionIsFocused)
                    .accessibilityIdentifier("item-description")
                }
            }

            private var panoramaArtwork: some View {
                Rectangle()
                    .fill(IrukandjiTheme.background)
                    .frame(height: artworkHeight)
                    .overlay {
                        GeometryReader { proxy in
                            ImageView(provider.item.imageSources(
                                for: .landscape,
                                environment: .init(maxWidth: 1920, viewContext: [.isBackdrop])
                            ))
                            .image { (image: Image) in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: proxy.size.width, height: proxy.size.height)
                            }
                            .failure { IrukandjiTheme.background }
                        }
                    }
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: IrukandjiTheme.background.opacity(0.35), location: 0),
                                .init(color: .clear, location: 0.25),
                                .init(color: .clear, location: 0.55),
                                .init(color: IrukandjiTheme.background, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .accessibilityHidden(true)
                    .overlay(alignment: .topLeading) {
                        if let parentID = provider.item.parentRootID, let parentTitle = provider.item.parentTitle {
                            ParentButton(title: parentTitle, id: parentID)
                                .edgePadding(.horizontal)
                                .padding(.top, 72)
                        }
                    }
            }

            private var panoramaDetails: some View {
                HStack(alignment: .center, spacing: 80) {
                    VStack(alignment: .leading, spacing: 14) {
                        MetadataHStack(item: provider.item)
                            .font(.system(size: 22))
                            .foregroundStyle(IrukandjiTheme.secondaryText)

                        Text(provider.item.displayTitle)
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        overview

                        AttributesHStack(
                            attributes: attributes,
                            item: provider.item,
                            selectedMediaSource: provider.mediaPlayerItemProvider?.mediaSource,
                            alignment: .leading
                        )
                        .font(.system(size: 18))
                        .foregroundStyle(IrukandjiTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ActionBar(provider: provider, alignment: .center, stacksPlaybackControls: true)
                        .frame(width: 360)
                }
                .edgePadding(.horizontal)
                .padding(.top, 20)
                .padding(.bottom, overviewText == nil ? 24 : 40)
                .focusSection()
            }

            @ViewBuilder
            private var episodeNavigation: some View {
                if provider.nextEpisodeItemProvider != nil || !provider.episodeSeasons.isEmpty {
                    VStack(spacing: 28) {
                        Rectangle()
                            .fill(.white.opacity(0.14))
                            .frame(height: 1)
                            .accessibilityHidden(true)

                        HStack(spacing: 40) {
                            if let next = provider.nextEpisodeItemProvider?.item {
                                NextEpisodeCard(item: next) {
                                    router.route(to: .item(item: next))
                                }
                            }

                            Spacer(minLength: 0)

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
                                .accessibilityIdentifier("item-seasons")
                            }
                        }
                        .focusSection()
                    }
                    .edgePadding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 56)
                }
            }

            private var panorama: some View {
                VStack(alignment: .leading, spacing: 0) {
                    panoramaArtwork
                    panoramaDetails
                    episodeNavigation
                }
                .frame(minHeight: viewportHeight - 60, alignment: .top)
                .background(IrukandjiTheme.background)
                .accessibilityElement(children: .contain)
            }

            private var compactOverview: some View {
                Group {
                    if let overviewText {
                        Text(overviewText)
                        .font(.system(size: 24))
                        .foregroundStyle(IrukandjiTheme.secondaryText)
                        .lineSpacing(5)
                        .lineLimit(3)
                    }
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
                        .foregroundStyle(IrukandjiTheme.secondaryText)
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

        @FocusState
        private var isFocused: Bool

        let item: BaseItemDto
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 24) {
                    ImageView(item.imageSources(
                        for: .landscape,
                        environment: .init(maxWidth: 400, useParent: false, viewContext: [.isThumb])
                    ))
                        .image { (image: Image) in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 200, height: 112.5)
                        }
                        .failure {
                            IrukandjiTheme.background
                                .overlay { Image(systemName: "film") }
                        }
                        .frame(width: 200, height: 112.5)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.next)
                            .font(.system(size: 20))

                        Text(item.displayTitle)
                            .font(.system(size: 28, weight: .medium))
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

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 20, weight: .medium))
                }
                .foregroundStyle(isFocused ? .white : IrukandjiTheme.secondaryText)
                .multilineTextAlignment(.leading)
                .padding(16)
                .frame(width: 660)
                .background(IrukandjiTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.focusBorder)
            .focused($isFocused)
            .accessibilityIdentifier("item-next-episode")
        }
    }
}
