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

    @State
    private var selection = CinematicItemSelection<Item>()

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
        selectedItem.map { AnyPoster($0) }
    }

    private var selectedItem: Item? {
        selection.item(in: items)
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
                    size: .medium,
                    onFocus: { selection.focus($0, in: items) }
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
        .focusSection()
    }
}

/// Retain a selection's identity, while always reading its current row data.
/// A removed Continue item must never remain in the cinematic preview.
struct CinematicItemSelection<Item: Identifiable> {

    private(set) var selectedID: Item.ID?

    func item(in items: [Item]) -> Item? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }

    mutating func focus(_ item: Item, in items: [Item]) {
        guard items.contains(where: { $0.id == item.id }) else { return }

        selectedID = item.id
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
