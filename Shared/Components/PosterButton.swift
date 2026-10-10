//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import SwiftUI

struct PosterButton<Item: Poster>: View {

    @Environment(\.viewContext)
    private var viewContext

    #if os(tvOS)
    @Environment(\.navigationFocusStore)
    private var navigationFocusStore
    @Environment(\.navigationFocusPageID)
    private var navigationFocusPageID
    @Environment(\.navigationFocusScopeID)
    private var navigationFocusScopeID

    private var returnFocusTarget: NavigationFocusStore.Target {
        .init(scope: navigationFocusScopeID, item: AnyHashable(item.id))
    }

    private func restoreFocus(_ request: NavigationFocusStore.Request?) {
        if request?.pageID == navigationFocusPageID, request?.target == returnFocusTarget {
            isFocused = true
        }
    }

    @FocusState
    private var isFocused: Bool
    #endif

    @Namespace
    private var namespace

    @State
    private var posterSize: CGSize = .zero

    let item: Item
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let action: (Namespace.ID) -> Void

    init(
        item: Item,
        displayType: PosterDisplayType,
        size: PosterDisplayType.Size = .small,
        action: @escaping (Namespace.ID) -> Void
    ) {
        self.item = item
        self.displayType = displayType
        self.size = size
        self.action = action
    }

    @ViewBuilder
    private var contextMenuPreview: some View {
        buttonLabel()
            .posterAccessibility(for: item)
            .frame(width: posterSize.width)
            .padding(20)
            .backport
            .glassEffect(in: .rect(cornerRadius: 10))
    }

    @ViewBuilder
    private func posterImage(overlay: some View) -> some View {
        PosterImage(
            item: item,
            type: displayType,
            size: size
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { overlay.posterStyle(displayType) }
        .contentShape(.contextMenuPreview, Rectangle())
        .matchedTransitionSource(id: "item", in: namespace)
        .subtleShadow()
        #if !os(tvOS)
            .hoverEffect(.highlight)
        #endif
    }

    @ViewBuilder
    private func buttonLabel(overlay: some View = EmptyView()) -> some View {
        VStack(alignment: .leading) {
            posterImage(overlay: overlay)

            item.posterLabel
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        Button {
            #if os(tvOS)
            navigationFocusStore?.remember(returnFocusTarget, on: navigationFocusPageID)
            #endif
            action(namespace)
        } label: {
            #if os(tvOS)
            VStack(alignment: .leading, spacing: 8) {
                posterImage(overlay: item.posterOverlay(for: displayType))
                    .posterAspectRatio(displayType, contentMode: .fit)
                    .posterCornerRadius(displayType)
                    .tvFocusBorder(
                        isFocused: isFocused,
                        shape: RoundedRectangle(
                            cornerRadius: posterSize.width * (displayType == .landscape ? 1 / 30 : 0.0375)
                        )
                    )
                    .posterAccessibility(for: item)

                item.posterLabel
                    .foregroundStyle(.white)
                    .opacity(isFocused ? 1 : 0.8)
                    .animation(.easeOut(duration: 0.12), value: isFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
            #else
            buttonLabel(overlay: item.posterOverlay(for: displayType))
                .posterAccessibility(for: item)
            #endif
        }
        .environment(\.posterDisplayType, displayType)
        .foregroundStyle(.primary, .secondary)
        #if os(tvOS)
            .buttonStyle(ArtworkButtonStyle())
            .focused($isFocused)
            .onAppear { restoreFocus(navigationFocusStore?.request) }
            .onChange(of: isFocused) { _, isFocused in
                if isFocused {
                    navigationFocusStore?.didRestore(returnFocusTarget, on: navigationFocusPageID)
                }
            }
            .onReceive(navigationFocusStore?.$request.eraseToAnyPublisher() ?? Combine.Empty<NavigationFocusStore.Request?, Never>()
                .eraseToAnyPublisher())
            { request in
                restoreFocus(request)
            }
        #else
            .buttonStyle(.borderless)
        #endif
            .buttonBorderShape(.roundedRectangle)
        #if os(tvOS)
            .focusedValue(\.focusedPoster, AnyPoster(item))
            .frame(maxWidth: .infinity, alignment: .leading)
            .ignoresSafeArea()
        #endif
            .trackingSize($posterSize)
            .posterContextMenu(for: item) {
                contextMenuPreview
                    .withViewContext(viewContext)
            }
    }
}
