//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct CinematicContentGroupContainer<Content: View>: View {

    @Environment(\.frameForParentView)
    private var frameForParentView

    @Environment(\.mainNavigationScrollContext)
    private var navigationScrollContext

    private let content: Content
    private let fillsViewport: Bool

    init(fillsViewport: Bool = false, @ViewBuilder content: () -> Content) {
        self.fillsViewport = fillsViewport
        self.content = content()
    }

    private var resolvedHeight: CGFloat {
        let parentHeight = frameForParentView[.scrollView, default: .zero].frame.height

        let headerHeight = navigationScrollContext == nil ? 0 : MainNavigationScrollController.headerHeight
        return max(parentHeight - headerHeight - (fillsViewport ? 0 : 75), 0)
    }

    var body: some View {
        content
            .frame(height: resolvedHeight, alignment: .bottomLeading)
            .frame(maxWidth: .infinity)
    }
}
