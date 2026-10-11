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

    struct ContentGroupScrollView: View {

        @Environment(\.tabSafeAreaInsets)
        private var tabSafeAreaInsets

        @EnvironmentObject
        private var focusCoordinator: FocusCoordinator

        @ObservedObject
        var provider: ItemContentGroupProvider

        let groups: [any ContentGroup]
        let isEnhanced: Bool

        private var isHeaderFocused: Bool {
            focusCoordinator.lastFocusedIDs.contains(Component.header)
        }

        private var backgroundImageItem: BaseItemDto {
            if provider.item.type == .person || provider.item.type == .musicArtist,
               let randomItem = provider.randomBackdropItem
            {
                randomItem
            } else {
                provider.item
            }
        }

        #if os(tvOS)
        private var background: some View {
            ZStack {
                IrukandjiTheme.background

                AlternateLayoutView {
                    Color.clear
                } content: {
                    ImageView(backgroundImageItem.imageSources(
                        for: .landscape,
                        environment: .init(maxWidth: 1920)
                    ))
                    .failure {
                        IrukandjiTheme.background
                    }
                    .aspectRatio(contentMode: .fill)
                }
                .saturation(0.75)
                .opacity(isHeaderFocused ? 0.65 : 0.12)

                LinearGradient(
                    stops: [
                        .init(color: IrukandjiTheme.background.opacity(0.1), location: 0),
                        .init(color: IrukandjiTheme.background.opacity(0.7), location: 0.6),
                        .init(color: IrukandjiTheme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
            .animation(.easeOut(duration: 0.2), value: isHeaderFocused)
        }
        #endif

        var body: some View {
            ZStack {
                #if os(tvOS)
                IrukandjiTheme.background
                    .ignoresSafeArea()

                if isEnhanced, provider.item.type == .person {
                    background
                        .ignoresSafeArea()
                }
                #endif

                ScrollView {
                    ContentGroupVStack(groups: groups)
                        .edgePadding(.bottom)
                        .padding(.top, isEnhanced ? 0 : tabSafeAreaInsets.top)
                }
                .trackingFrame(for: .scrollView)
                .mainNavigationScrollObserver()
                #if os(tvOS)
                    .ignoresSafeArea(.container, edges: isEnhanced ? .all : [.horizontal, .top])
                #else
                    .ignoresSafeArea(edges: isEnhanced ? .all : .horizontal)
                #endif
                    .scrollIndicators(.hidden)
            }
        }
    }
}
