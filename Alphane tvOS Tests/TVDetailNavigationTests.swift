//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import XCTest

final class TVDetailNavigationTests: XCTestCase {

    func testInfoCannotOpenWithoutAdditionalContent() {
        var navigation = TVDetailNavigation()
        navigation.showInfo(hasInfo: false)
        XCTAssertEqual(navigation.section, .playback)
        XCTAssertFalse(navigation.isEnteringInfo)
    }

    func testReturningFromInfoRestoresResumeOrNextInsteadOfTheInfoFocus() {
        for action in ["resume", "next"] {
            var navigation = TVDetailNavigation()
            let playbackIDs: Set<String> = ["resume", "next"]
            navigation.rememberFocus(["header", action], validPlaybackIDs: playbackIDs)
            navigation.showInfo(hasInfo: true)
            navigation.rememberFocus(["cast"], validPlaybackIDs: playbackIDs)
            navigation.infoDidReceiveFocus()
            navigation.showPlayback(validPlaybackIDs: playbackIDs, preferredFocusID: "resume")

            XCTAssertEqual(navigation.section, .playback)
            XCTAssertEqual(navigation.pendingPlaybackFocusID, action)
            navigation.playbackDidReceiveFocus(["header", action])
            XCTAssertNil(navigation.pendingPlaybackFocusID)
        }
    }

    func testCompactHeaderCannotBounceBackDuringTheInfoTransition() {
        var navigation = TVDetailNavigation()
        navigation.showInfo(hasInfo: true)
        navigation.showPlayback(validPlaybackIDs: ["play"], preferredFocusID: "play")
        XCTAssertEqual(navigation.section, .info)
        XCTAssertTrue(navigation.isEnteringInfo)

        navigation.infoDidReceiveFocus()
        navigation.showPlayback(validPlaybackIDs: ["play"], preferredFocusID: "play")
        XCTAssertEqual(navigation.section, .playback)
    }

    func testAnUnavailableActionFallsBackToTheCurrentPlaybackPreference() {
        var navigation = TVDetailNavigation()
        navigation.rememberFocus(["next"], validPlaybackIDs: ["play", "next"])
        navigation.showInfo(hasInfo: true)
        navigation.infoDidReceiveFocus()
        navigation.showPlayback(validPlaybackIDs: ["play"], preferredFocusID: "play")
        XCTAssertEqual(navigation.pendingPlaybackFocusID, "play")
    }

    func testTransientMultipleFocusIDsDoNotReplaceTheRememberedAction() {
        var navigation = TVDetailNavigation()
        navigation.rememberFocus(["liked"], validPlaybackIDs: ["liked", "play"])
        navigation.rememberFocus(["liked", "play"], validPlaybackIDs: ["liked", "play"])
        XCTAssertEqual(navigation.rememberedFocusID, "liked")

        navigation.rememberFocus(["play"], validPlaybackIDs: ["liked", "play"])
        XCTAssertEqual(navigation.rememberedFocusID, "play")
    }
}
