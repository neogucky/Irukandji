//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import SwiftUI
import XCTest

@MainActor
final class PersistentNavigationTests: XCTestCase {

    func testBrowsingPushesRemainInStackAndBackReturnsToPreviousPage() {
        let coordinator = NavigationCoordinator(usesNavigationStack: true)
        coordinator.push(route("series"))
        coordinator.push(route("episode"))

        XCTAssertEqual(coordinator.path.map(\.id), ["series", "episode"])
        XCTAssertNil(coordinator.presentedSheet)
        coordinator.path.removeLast()
        XCTAssertEqual(coordinator.path.map(\.id), ["series"])
    }

    func testFullscreenPlaybackPreservesBrowsingStack() {
        let coordinator = NavigationCoordinator(usesNavigationStack: true)
        coordinator.push(route("episode"))
        coordinator.push(route("player", style: .fullscreen))

        XCTAssertEqual(coordinator.path.map(\.id), ["episode"])
        XCTAssertEqual(coordinator.presentedFullScreen?.route.id, "player")
        XCTAssertNil(coordinator.presentedSheet)
    }

    func testExplicitModalStillPresentsAboveBrowsingStack() {
        let coordinator = NavigationCoordinator(usesNavigationStack: true)
        coordinator.push(route("episode"))
        coordinator.push(route("filters", style: .sheet))

        XCTAssertEqual(coordinator.path.map(\.id), ["episode"])
        XCTAssertEqual(coordinator.presentedSheet?.route.id, "filters")
    }

    func testNonTabNavigationRetainsExistingPresentationBehavior() {
        let coordinator = NavigationCoordinator()
        coordinator.push(route("connect"))

        XCTAssertTrue(coordinator.path.isEmpty)
        XCTAssertEqual(coordinator.presentedSheet?.route.id, "connect")
    }

    func testSwitchingTabsPreservesIndependentBrowsingHistory() async {
        let coordinator = TabCoordinator {
            TabItem(id: "home", title: "Home", systemImage: "house") { EmptyView() }
            TabItem(id: "movies", title: "Movies", systemImage: "film") { EmptyView() }
        }
        await coordinator.route(to: route("episode"))
        coordinator.selectedTabID = "movies"
        await coordinator.route(to: route("movie"))
        coordinator.selectedTabID = "home"

        XCTAssertEqual(coordinator.tabs[0].coordinator.path.map(\.id), ["episode"])
        XCTAssertEqual(coordinator.tabs[1].coordinator.path.map(\.id), ["movie"])
        XCTAssertNil(coordinator.tabs[0].coordinator.presentedSheet)
        XCTAssertNil(coordinator.tabs[1].coordinator.presentedSheet)
    }

    func testHeaderObservationDoesNotMutateScrollViewOrPublishPageUpdates() {
        let controller = MainNavigationScrollController()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        scrollView.contentInset.top = 80
        let viewport = scrollView.bounds.size
        var layoutUpdates = 0
        let subscription = controller.objectWillChange.sink { layoutUpdates += 1 }
        controller.register(scrollView, tabID: "home")
        controller.activate("home")

        for offset in stride(from: -80, through: 400, by: 1) {
            scrollView.contentOffset.y = CGFloat(offset)
            controller.didScroll(tabID: "home")
        }

        XCTAssertEqual(scrollView.bounds.size, viewport)
        XCTAssertEqual(controller.headerState.hiddenHeight, 80)
        XCTAssertEqual(layoutUpdates, 0)
        withExtendedLifetime(subscription) {}
    }

    func testHeaderUsesRememberedOffsetForActiveTabOnly() {
        let controller = MainNavigationScrollController()
        let home = UIScrollView()
        let movies = UIScrollView()
        home.contentOffset.y = 40
        movies.contentOffset.y = 200
        controller.register(home, tabID: "home")
        controller.register(movies, tabID: "movies")
        controller.activate("home")
        XCTAssertEqual(controller.headerState.hiddenHeight, 40)

        controller.didScroll(tabID: "movies")
        XCTAssertEqual(controller.headerState.hiddenHeight, 40)
        controller.activate("movies")
        XCTAssertEqual(controller.headerState.hiddenHeight, 80)
        controller.activate("home")
        XCTAssertEqual(controller.headerState.hiddenHeight, 40)
    }

    func testHeaderStopsPublishingOnceItHasScrolledAway() {
        let controller = MainNavigationScrollController()
        let scrollView = UIScrollView()
        controller.register(scrollView, tabID: "home")
        controller.activate("home")
        var headerUpdates = 0
        let subscription = controller.headerState.objectWillChange.sink { headerUpdates += 1 }

        for offset in stride(from: 0, through: 400, by: 1) {
            scrollView.contentOffset.y = CGFloat(offset)
            controller.didScroll(tabID: "home")
        }

        XCTAssertEqual(headerUpdates, 80)
        XCTAssertEqual(controller.headerState.hiddenHeight, 80)
        withExtendedLifetime(subscription) {}
    }

    func testBackRequestsTheActivatedCardOnItsOriginatingPage() {
        let coordinator = NavigationCoordinator(usesNavigationStack: true)
        let homeTarget = NavigationFocusStore.Target(scope: "continue", item: "episode-12")
        let seriesTarget = NavigationFocusStore.Target(scope: "episodes", item: "episode-13")
        coordinator.focusStore.remember(homeTarget, on: "root")
        coordinator.push(route("series"))
        XCTAssertNil(coordinator.focusStore.request)
        coordinator.focusStore.remember(seriesTarget, on: "series")
        coordinator.push(route("episode"))

        coordinator.path.removeLast()
        XCTAssertEqual(coordinator.focusStore.request?.pageID, "series")
        XCTAssertEqual(coordinator.focusStore.request?.target, seriesTarget)
        coordinator.path.removeLast()
        XCTAssertEqual(coordinator.focusStore.request?.pageID, "root")
        XCTAssertEqual(coordinator.focusStore.request?.target, homeTarget)
    }

    func testRestorationIsConsumedOnceSoMovingFocusDoesNotJumpBack() {
        let store = NavigationFocusStore()
        let target = NavigationFocusStore.Target(scope: "continue", item: "episode-12")
        store.remember(target, on: "root")
        store.restore("root")
        store.didRestore(target, on: "series")
        XCTAssertNotNil(store.request)
        store.didRestore(target, on: "root")
        XCTAssertNil(store.request)
        // Remembered activation remains available for another visit to the same detail page.
        store.restore("root")
        XCTAssertEqual(store.request?.target, target)
    }

    func testDetailDefaultFocusRemainsAvailableDuringNavigationTransition() {
        let coordinator = FocusCoordinator(initial: "play")
        XCTAssertNil(coordinator.request)
        XCTAssertTrue(coordinator.prefersInitialFocus("play"))
        XCTAssertFalse(coordinator.prefersInitialFocus("seasons"))

        // Native default preferences remain available if tvOS evaluates them again
        // after the transition; they do not issue another imperative focus request.
        coordinator.focus("seasons")
        XCTAssertTrue(coordinator.prefersInitialFocus("play"))
        XCTAssertEqual(coordinator.request?.id, "seasons")
    }

    private func route(
        _ id: String,
        style: NavigationRoute.TransitionStyle = .push(.automatic)
    ) -> NavigationRoute {
        NavigationRoute(id: id, style: style) { EmptyView() }
    }
}
