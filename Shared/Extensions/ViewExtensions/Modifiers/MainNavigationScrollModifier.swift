//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
#if os(tvOS)
@_spi(Advanced) import SwiftUIIntrospect

private struct MainNavigationScrollModifier: ViewModifier {

    @Environment(\.onMainNavigationScroll)
    private var onScroll

    @StateObject
    private var observer = ScrollObserver()

    func body(content: Content) -> some View {
        content.introspect(.scrollView, on: .tvOS(.v26...)) { scrollView in
            observer.observe(scrollView, onScroll: onScroll)
        }
    }

    @MainActor
    private final class ScrollObserver: ObservableObject {

        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var onScroll: ((CGFloat) -> Void)?

        func observe(_ scrollView: UIScrollView, onScroll: ((CGFloat) -> Void)?) {
            self.onScroll = onScroll
            guard self.scrollView !== scrollView else { return }

            self.scrollView = scrollView
            // CollectionVGrid needs its own delegate for paging and focus.
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] view, _ in
                let offset = max(0, view.contentOffset.y + view.adjustedContentInset.top)
                Task { @MainActor [weak self] in
                    self?.onScroll?(offset)
                }
            }
        }
    }
}
#endif

extension View {

    @ViewBuilder
    func mainNavigationScrollObserver() -> some View {
        #if os(tvOS)
        modifier(MainNavigationScrollModifier())
        #else
        self
        #endif
    }
}
