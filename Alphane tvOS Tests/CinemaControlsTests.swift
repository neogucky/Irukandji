//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI
@testable import Alphane
import XCTest

@MainActor
final class CinemaControlsTests: XCTestCase {

    func testControlsShowTransportWithoutTheOldSupplementTabRow() {
        let state = VideoPlayer.ViewState()
        state.presentGuestSupplement(TestSupplement())
        state.selectedSupplementID = nil
        state.showControls()

        XCTAssertEqual(state.presentation, .controls)
        XCTAssertTrue(state.visibleElements.contains(.toolbar))
        XCTAssertTrue(state.visibleElements.contains(.playbackButtons))
        XCTAssertTrue(state.visibleElements.contains(.progress))
        XCTAssertFalse(state.visibleElements.contains(.supplements))
    }

    func testOpeningEpisodesReplacesControlsAndBackRestoresThem() {
        let state = VideoPlayer.ViewState()
        state.showControls()
        state.presentGuestSupplement(TestSupplement())

        XCTAssertEqual(state.selectedSupplementID, "episodes")
        XCTAssertEqual(state.visibleElements, [.supplements, .dimming])

        state.selectedSupplementID = nil
        XCTAssertNil(state.selectedSupplementID)
        XCTAssertTrue(state.visibleElements.contains(.playbackButtons))
        XCTAssertFalse(state.visibleElements.contains(.supplements))
    }

    func testScrubbingShowsOnlyProgressAndRestoresTheTransportAfterward() {
        let state = VideoPlayer.ViewState()
        state.showControls()
        state.isScrubbing = true
        XCTAssertEqual(state.visibleElements, [.progress])

        state.cancelScrub()
        XCTAssertFalse(state.isScrubbing)
        XCTAssertTrue(state.visibleElements.contains(.playbackButtons))
    }

    func testProgressOnlySeekingDoesNotRevealTheCinemaButtonRow() {
        let state = VideoPlayer.ViewState()
        state.showProgress()
        XCTAssertEqual(state.presentation, .progress)
        XCTAssertEqual(state.visibleElements, [.progress])

        state.hideControls()
        XCTAssertTrue(state.visibleElements.isEmpty)
    }

    private struct TestSupplement: MediaPlayerSupplement {
        let id = "episodes"
        let displayTitle = "Episodes"
        var videoPlayerBody: some PlatformView {
            InlinePlatformView(iOSView: { EmptyView() }, tvOSView: { EmptyView() })
        }
    }
}
