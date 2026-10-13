//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

extension SeriesEpisodeContentGroup {

    struct EpisodeCard: View {

        @Namespace
        private var namespace

        @Router
        private var router

        @SharedBaseItem
        var episode: BaseItemDto

        private var episodeContent: String {
            if episode.isUnaired {
                episode.airDateLabel ?? L10n.noOverviewAvailable
            } else {
                episode.overview ?? L10n.noOverviewAvailable
            }
        }

        var body: some View {
            EpisodeCardLayout(
                header: episode.displayTitle,
                subHeader: episode.episodeLocator ?? .emptyDash,
                content: episodeContent,
                artworkAction: {
                    guard let provider = episode.getPlaybackItemProvider(userSession: nil) else {
                        return
                    }

                    router.route(
                        to: .videoPlayer(
                            provider: provider,
                            queue: EpisodeMediaPlayerQueue(episode: episode)
                        )
                    )
                },
                contentAction: {
                    router.route(to: .item(item: episode), in: namespace)
                },
                contextMenuItem: episode
            ) {
                PosterImage(
                    item: episode,
                    type: .landscape,
                    size: .medium
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    PosterIndicatorsOverlay(
                        item: episode,
                        posterDisplayType: .landscape
                    )
                }
                .contentShape(.contextMenuPreview, Rectangle())
                .subtleShadow()
                .matchedTransitionSource(id: "item", in: namespace)
            }
        }
    }

    struct EpisodeStateCard: View {

        let title: String
        let subHeader: String
        let content: String
        let systemImage: String?
        let action: () -> Void

        var body: some View {
            EpisodeCardLayout(
                header: title,
                subHeader: subHeader,
                content: content,
                artworkAction: action,
                contentAction: action
            ) {
                Rectangle()
                    .fill(.complexSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if let systemImage {
                            RelativeSystemImageView(systemName: systemImage)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .posterStyle(.landscape)
                #if os(tvOS)
                    .posterCornerRadius(.landscape)
                #endif
                    .subtleShadow()
            }
        }
    }

    private struct EpisodeCardLayout<Artwork: View>: View {

        private enum FocusedElement: Hashable {

            case artwork
            case content
        }

        @Environment(\.posterConfiguration)
        private var posterConfiguration

        @Environment(\.viewContext)
        private var viewContext

        @FocusState
        private var focusedElement: FocusedElement?

        @State
        private var artworkSize: CGSize = .zero

        let header: String
        let subHeader: String
        let content: String
        let artworkAction: () -> Void
        let contentAction: () -> Void
        @OptionalSharedBaseItem
        var contextMenuItem: BaseItemDto?
        let artwork: Artwork

        private var contentAccessibilityLabel: String {
            let title = contextMenuItem?.posterAccessibility(configuration: posterConfiguration).label
            return PosterAccessibility.joined([title ?? header, contextMenuItem == nil ? subHeader : nil, content])
        }

        init(
            header: String,
            subHeader: String,
            content: String,
            artworkAction: @escaping () -> Void,
            contentAction: @escaping () -> Void,
            contextMenuItem: BaseItemDto? = nil,
            @ViewBuilder artwork: () -> Artwork
        ) {
            self.header = header
            self.subHeader = subHeader
            self.content = content
            self.artworkAction = artworkAction
            self.contentAction = contentAction
            self.contextMenuItem = contextMenuItem
            self.artwork = artwork()
        }

        @ViewBuilder
        private func contextMenuPreview(for item: BaseItemDto) -> some View {
            VStack(alignment: .leading) {
                PosterImage(
                    item: item,
                    type: .landscape,
                    size: .medium,
                    contentMode: .fit
                )
                .subtleShadow()

                item.posterLabel
                    .allowsHitTesting(false)
            }
            .environment(\.posterDisplayType, .landscape)
            .foregroundStyle(.primary, .secondary)
            .posterAccessibility(for: item)
            .frame(width: artworkSize.width)
            .padding(20)
            .backport
            .glassEffect(in: .rect(cornerRadius: 10))
        }

        @ViewBuilder
        private var artworkButton: some View {
            let button = Button(action: artworkAction) {
                Group {
                    if let contextMenuItem {
                        artwork
                            .posterAccessibility(for: contextMenuItem)
                            .accessibilityHint(L10n.posterAccessibilityPlayHint)
                    } else {
                        artwork
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(PosterAccessibility.joined([header, subHeader]))
                    }
                }
                #if os(tvOS)
                // Clip the artwork before the button style draws its outside focus border.
                .clipShape(RoundedRectangle(cornerRadius: 20))
                #endif
            }
            .foregroundStyle(.primary, .secondary)
            #if os(tvOS)
                .buttonStyle(.focusBorder)
            #else
                .buttonStyle(.card)
            #endif
                .focused($focusedElement, equals: .artwork)

            if let contextMenuItem {
                button
                    .trackingSize($artworkSize)
                    .posterContextMenu(for: contextMenuItem) {
                        contextMenuPreview(for: contextMenuItem)
                            .withViewContext(viewContext)
                    }
            } else {
                button
            }
        }

        var body: some View {
            VStack(alignment: .leading) {
                artworkButton
                    .posterAspectRatio(.landscape, contentMode: .fit)

                Button(action: contentAction) {
                    EpisodeMetadataView(
                        header: header,
                        subHeader: subHeader,
                        content: content,
                        isHighlighted: focusedElement != nil
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(contentAccessibilityLabel)
                    .accessibilityHint(contextMenuItem == nil ? "" : L10n.posterAccessibilityDetailsHint)
                }
                .foregroundStyle(.primary, .secondary)
                #if os(tvOS)
                    .buttonStyle(
                        EpisodeContentButtonStyle(
                            isFocused: focusedElement == .content
                        )
                    )
                #endif
                    .focused($focusedElement, equals: .content)
            }
            .focusSection()
            .defaultFocus(
                $focusedElement,
                .artwork,
                priority: .userInitiated
            )
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private struct EpisodeMetadataView: View {

        let header: String
        let subHeader: String
        let content: String
        let isHighlighted: Bool

        private func textStyle(_ style: HierarchicalShapeStyle) -> AnyShapeStyle {
            #if os(tvOS)
            AnyShapeStyle(Color.white.opacity(isHighlighted ? 1 : 0.8))
            #else
            AnyShapeStyle(style)
            #endif
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(subHeader)
                    .font(.caption)
                    .foregroundStyle(textStyle(.secondary))
                    .lineLimit(1)

                Text(header)
                    .font(.headline)
                    .foregroundStyle(textStyle(.primary))
                    .lineLimit(1)

                SeeMoreText(content)
                    .font(.caption)
                    .foregroundStyle(textStyle(.secondary))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #if os(tvOS)
    private struct EpisodeContentButtonStyle: ButtonStyle {

        let isFocused: Bool

        private let cornerRadius: CGFloat = 20

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .padding(28)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
                .frame(height: 200)
                .tvFocusBorder(isFocused: isFocused, shape: RoundedRectangle(cornerRadius: cornerRadius))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
    #endif
}
