//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct CinematicItemSelector<Item: Poster, TopContent: View>: View {

    @Environment(\.frameForParentView)
    private var frameForParentView

    @Environment(\.mainNavigationScrollContext)
    private var navigationScrollContext

    private var headerHeight: CGFloat {
        navigationScrollContext == nil ? 0 : MainNavigationScrollController.headerHeight
    }

    @FocusState
    private var isSectionFocused

    @FocusedValue(\.focusedPoster)
    private var focusedPoster

    @State
    private var selectedPoster: AnyPoster?

    private let action: (Item) -> Void
    private let items: [Item]
    private let topContent: (Item) -> TopContent

    init(
        items: [Item],
        action: @escaping (Item) -> Void,
        @ViewBuilder topContent: @escaping (Item) -> TopContent
    ) {
        self.items = items
        self.action = action
        self.topContent = topContent
    }

    private var parentFrame: CGRect {
        frameForParentView[.scrollView, default: .zero].frame
    }

    private var resolvedSelectedPoster: AnyPoster? {
        selectedPoster ?? items.first.map { AnyPoster($0) }
    }

    private var selectedItem: Item? {
        resolvedSelectedPoster?._poster as? Item
    }

    private func updateSelectedPoster() {
        guard isSectionFocused, let focusedPoster else { return }

        selectedPoster = focusedPoster
    }

    var body: some View {
        CinematicContentGroupContainer(fillsViewport: true) {
            VStack(alignment: .leading, spacing: 28) {

                if let selectedItem {
                    topContent(selectedItem)
                        .frame(height: 340, alignment: .bottomLeading)
                        .id(selectedItem.hashValue)
                        .transition(.opacity)
                }

                // TODO: fix intrinsic content sizing without frame
                PosterHStack(
                    elements: items,
                    displayType: .landscape,
                    size: .medium
                ) { item, _ in
                    action(item)
                }
                .frame(height: 350)
            }
            .padding(.bottom, 32)
        }
        .background(alignment: .top) {
            FadeContentTransitionView(
                item: resolvedSelectedPoster,
                debounce: 0.3
            ) { item in
                ImageView(item?.imageSources(for: .landscape, environment: .init(viewContext: .isBackdrop)) ?? [])
                    .failure {
                        EmptyView()
                    }
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: parentFrame.width, height: parentFrame.height)
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: AlphaneTheme.background.opacity(0.85), location: 0),
                        .init(color: AlphaneTheme.background.opacity(0.72), location: 0.4),
                        .init(color: .clear, location: 0.75),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.5),
                        .init(color: AlphaneTheme.background.opacity(0.8), location: 0.82),
                        .init(color: AlphaneTheme.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .offset(y: -headerHeight)
        }
        .background(AlphaneTheme.background)
        .onChange(of: focusedPoster) {
            updateSelectedPoster()
        }
        .onChange(of: isSectionFocused) {
            updateSelectedPoster()
        }
        .focusSection()
        .focused($isSectionFocused)
    }
}

extension CinematicItemSelector where TopContent == EmptyView {

    init(
        items: [Item],
        action: @escaping (Item) -> Void = { _ in }
    ) {
        self.init(
            items: items,
            action: action
        ) { _ in
            EmptyView()
        }
    }
}
