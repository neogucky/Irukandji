//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import Foundation
import JellyfinAPI
import XCTest

@MainActor
final class UserSessionForegroundTests: XCTestCase {
    func testWakeRetainsTheLiveStoreAndItsLoadedCollections() async throws {
        let current = session()
        let record = try current.items.record(for: BaseItemDto(id: "movie", name: "Cached movie", type: .movie))
        let library = StaticLibrary(title: "Cached", id: "cached", elements: [ItemEntry(item: record)])
        let rows = PagingLibraryViewModel(library: library, userSession: current)
        await rows.refresh()

        let resumed = try XCTUnwrap(UserSession.sessionForForeground(current: current, stored: session()))
        XCTAssertTrue(resumed === current)
        XCTAssertTrue(resumed.items === current.items)
        XCTAssertTrue(resumed.items.isActive)
        XCTAssertEqual(rows.elements.count, 1)
        XCTAssertEqual(rows.elements.first?.snapshot.name, "Cached movie")
        // Loaded paging models must remain refreshable after foregrounding.
        await rows.refresh()
        XCTAssertEqual(rows.elements.first?.itemID, "movie")
        XCTAssertEqual(rows.state, .content)
    }

    func testChangedAuthenticationOrEndpointRequiresARealSessionReplacement() throws {
        let current = session()
        for stored in try [
            session(userID: "other-user"),
            session(serverID: "other-server"),
            session(token: "new-token"),
            session(url: XCTUnwrap(URL(string: "https://other.example.com")))
        ] {
            let resumed = UserSession.sessionForForeground(current: current, stored: stored)
            XCTAssertTrue(resumed === stored)
            XCTAssertFalse(resumed === current)
        }
    }

    func testForegroundStillHonoursSignOutAndDeletedProfiles() {
        XCTAssertNil(UserSession.sessionForForeground(current: session(), stored: nil))
        let stored = session()
        XCTAssertTrue(UserSession.sessionForForeground(current: nil, stored: stored) === stored)
        XCTAssertNil(UserSession.sessionForForeground(current: nil, stored: nil))
    }

    private func session(
        serverID: String = "server",
        userID: String = "user",
        token: String = "test-token",
        url: URL = URL(string: "https://example.com")!
    ) -> UserSession {
        let session = UserSession(
            server: ServerState(urls: [url], currentURL: url, name: "Server", id: serverID, userIDs: [userID]),
            user: UserState(id: userID, serverID: serverID, username: "User")
        )
        // Fake credentials stay in memory; no Keychain or server access.
        session.client = JellyfinClient(configuration: .alphaneConfiguration(url: url, accessToken: token))
        return session
    }
}
