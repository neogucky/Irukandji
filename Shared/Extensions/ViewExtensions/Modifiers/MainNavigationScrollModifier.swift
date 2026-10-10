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

struct MainNavigationScrollContext {
    let controller: MainNavigationScrollController
    let tabID: String
}

/// Only the header observes scroll position; tab content keeps a fixed viewport and focus hierarchy.
@MainActor
final class MainNavigationHeaderState: ObservableObject {

    @Published
    private(set) var hiddenHeight: CGFloat = 0

    func update(hiddenHeight: CGFloat) {
        guard self.hiddenHeight != hiddenHeight else { return }

        self.hiddenHeight = hiddenHeight
    }
}

/// Keeps scroll changes out of the tab content's observation path.
@MainActor
final class MainNavigationScrollController: ObservableObject {

    static let headerHeight: CGFloat = 80

    private final class ScrollReference {
        weak var view: UIScrollView?
        init(_ view: UIScrollView) {
            self.view = view
        }
    }

    private var scrollViews: [String: ScrollReference] = [:]
    private var activeTabID: String?
    let headerState = MainNavigationHeaderState()

    func register(_ scrollView: UIScrollView, tabID: String) {
        scrollViews[tabID] = ScrollReference(scrollView)
        updateHeader()
    }

    func activate(_ tabID: String) {
        activeTabID = tabID
        updateHeader()
    }

    func didScroll(tabID: String) {
        guard tabID == activeTabID else { return }

        updateHeader()
    }

    func revealHeader() {
        guard let activeTabID, let view = scrollViews[activeTabID]?.view else { return }

        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: true)
    }

    private func updateHeader() {
        let scrollView = activeTabID.flatMap { scrollViews[$0]?.view }
        let offset = scrollView.map { max(0, $0.contentOffset.y + $0.adjustedContentInset.top) } ?? 0
        headerState.update(hiddenHeight: min(offset, Self.headerHeight))
    }
}

/// A regular SwiftUI view shares the tab's focus graph. Observing only this small view avoids
/// rebuilding the pages during scrolling, without a separate UIHostingController focus boundary.
struct MainNavigationHeaderHost<Content: View>: View {

    @ObservedObject
    var state: MainNavigationHeaderState
    @ViewBuilder
    let content: () -> Content

    var body: some View {
        content()
            .offset(y: -state.hiddenHeight)
    }
}

private struct MainNavigationScrollModifier: ViewModifier {

    @Environment(\.mainNavigationScrollContext)
    private var navigationContext

    @StateObject
    private var observer = ScrollObserver()

    func body(content: Content) -> some View {
        content.introspect(.scrollView, on: .tvOS(.v26...)) { scrollView in
            observer.observe(scrollView, context: navigationContext)
        }
    }

    @MainActor
    private final class ScrollObserver: ObservableObject {

        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var navigationContext: MainNavigationScrollContext?

        func observe(_ scrollView: UIScrollView, context: MainNavigationScrollContext?) {
            guard let context else {
                observation = nil
                self.scrollView = nil
                navigationContext = nil
                return
            }

            navigationContext = context
            guard self.scrollView !== scrollView else { return }

            self.scrollView = scrollView
            // Observe only. SwiftUI reserves header space in its own content layout,
            // keeping tvOS's focus-item coordinates in sync with the scroll view.
            context.controller.register(scrollView, tabID: context.tabID)

            // CollectionVGrid needs its own delegate for paging and focus.
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let context = self?.navigationContext else { return }

                    context.controller.didScroll(tabID: context.tabID)
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
