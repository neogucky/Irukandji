//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import JellyfinAPI
import XCTest

final class CinematicItemSelectionTests: XCTestCase {

    func testCompletedContinueItemCannotRemainInPreview() {
        let cad = BaseItemDto(id: "cad", name: "CAD", type: .episode)
        let movie = BaseItemDto(id: "movie", name: "Movie", type: .movie)
        var selection = CinematicItemSelection<BaseItemDto>()
        selection.focus(cad, in: [cad, movie])
        XCTAssertEqual(selection.item(in: [cad, movie])?.id, cad.id)
        XCTAssertEqual(selection.item(in: [movie])?.id, movie.id)
        XCTAssertNil(selection.item(in: []))
    }

    func testPreviewFollowsRestoredFocusEvenWhenItIsNotTheFirstCard() {
        let first = BaseItemDto(id: "first", name: "First", type: .movie)
        let focused = BaseItemDto(id: "focused", name: "Focused", type: .movie)
        var selection = CinematicItemSelection<BaseItemDto>()
        selection.focus(focused, in: [first, focused])
        XCTAssertEqual(selection.item(in: [first, focused])?.id, focused.id)
        // Ignore a late focus event from a cell removed during refresh.
        selection.focus(BaseItemDto(id: "removed"), in: [first, focused])
        XCTAssertEqual(selection.item(in: [first, focused])?.id, focused.id)
    }

    func testPreviewUsesRefreshedMetadataForTheSameFocusedItem() {
        let old = BaseItemDto(id: "movie", name: "Old title", overview: "Old description", type: .movie)
        var updated = old
        updated.name = "Updated title"
        updated.overview = "Updated description"
        var selection = CinematicItemSelection<BaseItemDto>()
        selection.focus(old, in: [old])
        XCTAssertEqual(selection.item(in: [updated])?.name, updated.name)
        XCTAssertEqual(selection.item(in: [updated])?.overview, updated.overview)
    }
}
