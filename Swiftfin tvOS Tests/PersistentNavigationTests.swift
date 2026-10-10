//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Swiftfin
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

    private func route(
        _ id: String,
        style: NavigationRoute.TransitionStyle = .push(.automatic)
    ) -> NavigationRoute {
        NavigationRoute(id: id, style: style) { EmptyView() }
    }
}
