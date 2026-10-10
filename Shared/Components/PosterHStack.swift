//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CollectionHStack
import SwiftUI

struct PosterHStack<
    Data: Collection
>: View where Data.Element: Poster, Data.Index == Int {

    #if os(tvOS)
    @Environment(\.navigationFocusStore)
    private var navigationFocusStore
    @Environment(\.navigationFocusPageID)
    private var navigationFocusPageID

    @State
    private var focusScopeID = UUID().uuidString
    #endif

    let elements: Data
    let displayType: PosterDisplayType
    let size: PosterDisplayType.Size
    let action: (Data.Element, Namespace.ID) -> Void

    private var layout: CollectionHStackLayout {
        #if os(tvOS)
        .grid(
            columns: displayType == .landscape ? 5 : 7,
            rows: 1,
            columnTrailingInset: 0
        )
        #else
        if UIDevice.isPad {
            let minWidth: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    220
                case (.landscape, .medium):
                    300
                case (_, .small):
                    140
//                case (_, .medium):
                default:
                    200
                }
            }()

            return .minimumWidth(
                columnWidth: minWidth,
                rows: 1
            )
        } else {
            let columnCount: CGFloat = {
                switch (displayType, size) {
                case (.landscape, .small):
                    2
                case (.landscape, .medium):
                    1.5
                case (_, .small):
                    3
//                case (_, .medium):
                default:
                    2
                }
            }()

            return .grid(
                columns: columnCount,
                rows: 1,
                columnTrailingInset: 0
            )
        }
        #endif
    }

    var body: some View {
        CollectionHStack(
            uniqueElements: elements,
            layout: layout
        ) { item in
            PosterButton(
                item: item,
                displayType: displayType,
                size: size
            ) { namespace in
                action(item, namespace)
            }
            #if os(tvOS)
            // CollectionHStack creates independent UIHostingControllers for its cells.
            // Pass the originating page's focus context into those roots explicitly.
            .environment(\.navigationFocusStore, navigationFocusStore)
            .environment(\.navigationFocusPageID, navigationFocusPageID)
            .environment(\.navigationFocusScopeID, focusScopeID)
            #endif
        }
        .clipsToBounds(false)
        // UIKit rounds the viewport to physical pixels. Leave enough height so a
        // fractional item height cannot exceed it and invalidate tvOS flow layout.
        .insets(horizontal: EdgeInsets.edgePadding, vertical: UIDevice.isTV ? 1 : 0)
        .itemSpacing(EdgeInsets.itemSpacing)
        .scrollBehavior(.continuousLeadingEdge)
        .withViewContext(.isThumb)
    }
}
