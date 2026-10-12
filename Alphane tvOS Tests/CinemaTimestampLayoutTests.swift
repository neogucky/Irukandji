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

final class CinemaTimestampLayoutTests: XCTestCase {

    private typealias Layout = VideoPlayer.PlaybackControls.CinemaTimestampLayout

    func testTimestampFollowsThePlayheadWithAndWithoutThePauseIcon() {
        XCTAssertEqual(Layout.elapsedOffset(progress: 0.25, trackWidth: 1800, labelWidth: 80), 410)
        XCTAssertEqual(Layout.elapsedOffset(progress: 0.25, trackWidth: 1800, labelWidth: 110), 395)
        XCTAssertEqual(Layout.elapsedOffset(progress: 0.5, trackWidth: 1800, labelWidth: 110), 845)
    }

    func testStartAndEndKeepTheWholeTimestampOnScreen() {
        XCTAssertEqual(Layout.elapsedOffset(progress: 0, trackWidth: 1800, labelWidth: 110), 0)
        XCTAssertEqual(Layout.elapsedOffset(progress: 1, trackWidth: 1800, labelWidth: 110), 1690)
        XCTAssertEqual(Layout.elapsedOffset(progress: -1, trackWidth: 1800, labelWidth: 110), 0)
        XCTAssertEqual(Layout.elapsedOffset(progress: 2, trackWidth: 1800, labelWidth: 110), 1690)
    }

    func testCountdownDoesNotOverlapTheElapsedTimeNearTheEnd() {
        XCTAssertTrue(Layout.showsRemainingTime(elapsedOffset: 800, elapsedWidth: 110, remainingWidth: 80, trackWidth: 1800))
        XCTAssertFalse(Layout.showsRemainingTime(elapsedOffset: 1620, elapsedWidth: 110, remainingWidth: 80, trackWidth: 1800))
        XCTAssertFalse(Layout.showsRemainingTime(elapsedOffset: 1690, elapsedWidth: 110, remainingWidth: 80, trackWidth: 1800))
    }

    func testUnmeasuredAndInvalidGeometryDoesNotProduceInvalidOffsets() {
        XCTAssertEqual(Layout.elapsedOffset(progress: 0.5, trackWidth: 0, labelWidth: 110), 0)
        XCTAssertEqual(Layout.elapsedOffset(progress: 0.5, trackWidth: 50, labelWidth: 110), 0)
        XCTAssertEqual(Layout.elapsedOffset(progress: .nan, trackWidth: 1800, labelWidth: 110), 0)
        XCTAssertEqual(Layout.elapsedOffset(progress: 0.5, trackWidth: .infinity, labelWidth: 110), 0)
        XCTAssertFalse(Layout.showsRemainingTime(elapsedOffset: 0, elapsedWidth: 0, remainingWidth: 0, trackWidth: 0))
    }
}
