//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
@testable import Alphane
import XCTest

final class LibraryFolderTests: XCTestCase {

    func testFolderLibrariesBrowseDirectChildrenIncludingNestedFolders() {
        let parents = [
            BaseItemDto(type: .folder),
            BaseItemDto(type: .collectionFolder),
            BaseItemDto(type: .userView),
            BaseItemDto(collectionType: .folders, type: .collectionFolder),
            BaseItemDto(collectionType: .folders, type: .userView),
        ]

        for parent in parents {
            XCTAssertFalse(parent.isRecursiveCollection)
            XCTAssertTrue(parent.supportedItemTypes.contains(.folder))
            XCTAssertTrue(parent.supportedItemTypes.contains(.collectionFolder))
            XCTAssertTrue(parent.supportedItemTypes.contains(.movie))
        }
    }

    func testMovieAndSeriesLibrariesKeepTheirExistingGrouping() {
        let movies = BaseItemDto(collectionType: .movies, type: .collectionFolder)
        XCTAssertEqual(movies.supportedItemTypes, [.movie])
        XCTAssertTrue(movies.isRecursiveCollection)

        let series = BaseItemDto(collectionType: .tvshows, type: .collectionFolder)
        XCTAssertEqual(series.supportedItemTypes, [.series])
        XCTAssertFalse(series.isRecursiveCollection)
        XCTAssertEqual(series.supportedItemTypes(for: .episodes), [.episode])
        XCTAssertTrue(series.isRecursiveCollection(for: .episodes))
        XCTAssertEqual(series.supportedItemTypes(for: .seasons), [.season])
        XCTAssertTrue(series.isRecursiveCollection(for: .seasons))
    }

    func testTypedBoxSetAndMusicCollectionsKeepTheirExistingBehavior() {
        let boxSets = BaseItemDto(collectionType: .boxsets, type: .collectionFolder)
        XCTAssertFalse(boxSets.isRecursiveCollection)
        XCTAssertFalse(boxSets.supportedItemTypes.contains(.folder))

        let music = BaseItemDto(collectionType: .music, type: .collectionFolder)
        XCTAssertEqual(music.supportedItemTypes, [.audio, .musicAlbum, .musicArtist])
        XCTAssertTrue(music.isRecursiveCollection)
    }

    func testFolderArtworkUsesTheSameLandscapeShapeAsFolderCards() {
        XCTAssertEqual(BaseItemKind.collectionFolder.preferredPosterDisplayType, .landscape)
        XCTAssertEqual(ImageType.primary.posterDisplayType(for: .collectionFolder), .landscape)
        XCTAssertEqual(BaseItemKind.movie.preferredPosterDisplayType, .portrait)
        XCTAssertEqual(ImageType.primary.posterDisplayType(for: .movie), .portrait)
    }
}
