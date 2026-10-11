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

@MainActor
final class TVProfilePickerTests: XCTestCase {

    func testSavedProfilesAreExcludedFromOtherUsersWithoutHidingUsersOnAnotherServer() {
        let server = makeServer("one")
        let saved = [
            UserState(id: "saved", serverID: "one", username: "Saved"),
            UserState(id: "same-id", serverID: "two", username: "Elsewhere")
        ]
        let publicUsers = [UserDto(id: "saved", name: "Saved"), UserDto(id: "same-id", name: "Other"), UserDto(id: "new", name: "New")]
        let profiles = SelectUserView.TVProfilePicker.unsavedProfiles(users: publicUsers, server: server, savedUsers: saved)
        XCTAssertEqual(profiles.map(\.user.id), ["new", "same-id"])
    }

    func testInvalidAndDuplicatePublicUsersDoNotCreateUnselectableOrDuplicateCards() {
        let users = [
            UserDto(name: "Missing"),
            UserDto(id: "", name: "Empty"),
            UserDto(id: "valid", name: "Valid"),
            UserDto(id: "valid", name: "Duplicate")
        ]
        let profiles = SelectUserView.TVProfilePicker.unsavedProfiles(users: users, server: makeServer("one"), savedUsers: [])
        XCTAssertEqual(profiles.map(\.id), ["one:valid"])
    }

    func testFocusIdentityDistinguishesTheSameUserIDOnDifferentServers() {
        XCTAssertNotEqual(
            SelectUserView.TVProfilePicker.profileID(userID: "user", serverID: "one"),
            SelectUserView.TVProfilePicker.profileID(userID: "user", serverID: "two")
        )
    }

    private func makeServer(_ id: String) -> ServerState {
        let url = URL(string: "https://example.com")!
        return ServerState(urls: [url], currentURL: url, name: id, id: id, userIDs: [])
    }
}
