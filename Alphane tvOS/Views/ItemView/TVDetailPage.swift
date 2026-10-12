//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct TVDetailPage: View {

        private enum Focus {
            static let moreInfo = "item-detail.more-info"
            static let returnToPlayback = "item-detail.return"
            static let compactPlay = "item-detail.compact-play"
        }

        @Environment(\.accessibilityReduceMotion)
        private var reduceMotion
        @Environment(\.initialFocusSelection)
        private var initialFocusSelection
        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        @FocusState
        private var boundaryFocus: String?
        @State
        private var navigation = TVDetailNavigation()

        private var buttonConfiguration = ItemActionButtons.Configuration()

        @ObservedObject var provider: ItemContentGroupProvider
        let groups: [any ContentGroup]
        let preferredPlaybackFocus: String

        private var infoGroups: [any ContentGroup] {
            groups.filter { $0.id == "item-metadata" } + groups.filter { $0.id != "item-metadata" }
        }

        private var validPlaybackFocusIDs: Set<String> {
            let (visible, _, _) = buttonConfiguration.resolvedButtons(for: provider)
            var ids = Set(visible.map(\.id))
            ids.formUnion([Component.play, Component.menu, Component.parent, Component.description, Component.seasons])
            if provider.item.userData?.isPlayed == true, provider.nextEpisodeItemProvider != nil {
                ids.insert(Component.nextEpisode)
            }
            return ids
        }

        private var firstInfoFocusID: String? {
            if infoGroups.first?.id == "item-metadata" {
                return TVDetailMetadataContentGroup.preferredFocusID(for: provider.item)
            }
            return infoGroups.first?.id
        }

        private func showInfo() {
            navigation.showInfo(hasInfo: !infoGroups.isEmpty)
        }

        private func showPlayback() {
            navigation.showPlayback(validPlaybackIDs: validPlaybackFocusIDs, preferredFocusID: preferredPlaybackFocus)
        }

        private func directionCue(up: Bool) -> some View {
            Button(action: up ? showPlayback : showInfo) {
                VStack(spacing: 8) {
                    if up { Image(systemName: "chevron.up") }
                    // swiftlint:disable:next hard_coded_display_string
                    Text(up ? "Up to return" : "Down for more info")
                    if !up { Image(systemName: "chevron.down") }
                }
                .font(.system(size: 20, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(DetailDirectionCueStyle())
            .coordinatedFocus(up ? Focus.returnToPlayback : Focus.moreInfo, selection: $boundaryFocus)
            .disabled(up && navigation.isEnteringInfo)
            .accessibilityIdentifier(up ? "detail-return" : "detail-more-info")
        }

        private func playbackSection(height: CGFloat) -> some View {
            TVDetailHeaderContentGroup.Body(
                provider: provider,
                viewportHeightOverride: height,
                showsArtwork: false,
                bottomPadding: infoGroups.isEmpty ? 72 : 150
            )
            .coordinatedFocus(Component.header)
            .overlay(alignment: .bottom) {
                if !infoGroups.isEmpty {
                    directionCue(up: false)
                        .padding(.bottom, 30)
                        .focusSection()
                }
            }
            .task {
                guard let target = navigation.pendingPlaybackFocusID else { return }

                await Task.yield()
                initialFocusSelection?.wrappedValue = target
                focusCoordinator.focus(target)
            }
        }

        private var compactHeader: some View {
            HStack(alignment: .center, spacing: 60) {
                VStack(alignment: .leading, spacing: 12) {
                    if let parentTitle = provider.item.parentTitle {
                        Text(parentTitle)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(AlphaneTheme.secondaryText)
                    }
                    Text(provider.item.displayTitle)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if provider.item.presentPlayButton {
                    PlayButton(provider: provider)
                        .coordinatedFocus(Focus.compactPlay, selection: $boundaryFocus)
                        .disabled(navigation.isEnteringInfo)
                }
            }
            .edgePadding(.horizontal)
            .focusSection()
        }

        private var infoSection: some View {
            VStack(spacing: 24) {
                directionCue(up: true)
                    .padding(.top, 24)
                compactHeader
                Divider().overlay(.white.opacity(0.12)).edgePadding(.horizontal)

                ScrollView {
                    ContentGroupVStack(groups: infoGroups, interGroupSpacing: 36)
                        .padding(.top, 8)
                        .edgePadding(.bottom)
                }
                .scrollIndicators(.hidden)
                .trackingFrame(for: .scrollView)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {
                guard let target = firstInfoFocusID else { return }

                await Task.yield()
                focusCoordinator.focus(target)
            }
        }

        var body: some View {
            GeometryReader { geometry in
                ZStack {
                    TVDetailArtwork(provider: provider, isShowingInfo: navigation.section == .info)

                    if navigation.section == .playback {
                        playbackSection(height: geometry.size.height)
                            .transition(.opacity)
                    } else {
                        infoSection
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: navigation.section)
            .onChange(of: boundaryFocus) { _, focus in
                if focus == Focus.moreInfo {
                    showInfo()
                } else if focus == Focus.returnToPlayback || focus == Focus.compactPlay {
                    showPlayback()
                }
            }
            .onReceive(focusCoordinator.$focusedIDs) { ids in
                navigation.rememberFocus(ids, validPlaybackIDs: validPlaybackFocusIDs)
                navigation.playbackDidReceiveFocus(ids)
                if navigation.section == .info,
                   ids.contains(where: { focusID in
                       focusID.hasPrefix("item-info.") || infoGroups.contains(where: { $0.id == focusID })
                   })
                {
                    navigation.infoDidReceiveFocus()
                }
            }
        }
    }
}

struct TVDetailArtwork: View {

    @ObservedObject var provider: ItemContentGroupProvider
    let isShowingInfo: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                AlphaneTheme.background
                ImageView(provider.item.imageSources(
                    for: .landscape,
                    environment: .init(maxWidth: 1920, viewContext: [.isBackdrop])
                ))
                .image { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                }
                .failure { AlphaneTheme.background }
                .opacity(isShowingInfo ? 0.16 : 1)

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: AlphaneTheme.background.opacity(0.02), location: 0.24),
                        .init(color: AlphaneTheme.background.opacity(0.56), location: 0.52),
                        .init(color: AlphaneTheme.background.opacity(0.94), location: 0.76),
                        .init(color: AlphaneTheme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [AlphaneTheme.background.opacity(0.22), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DetailDirectionCueStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.white : AlphaneTheme.secondaryText)
    }
}
