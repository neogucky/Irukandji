//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

#if targetEnvironment(simulator)
import Foundation
import Security
import XCTest

final class SimulatorKeychainTests: XCTestCase {

    func testLoginKeychainGroupSurvivesSimulatorSigning() throws {
        let identifier = try XCTUnwrap(Bundle.main.bundleIdentifier)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Alphane Simulator Signing Check",
            kSecAttrAccount as String: "disposable-\(UUID().uuidString)",
            kSecAttrAccessGroup as String: identifier,
        ]
        let value = Data("disposable-test-value".utf8)
        var addQuery = query
        addQuery[kSecValueData as String] = value
        defer { SecItemDelete(query as CFDictionary) }

        XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)

        // KeychainSwift reads without specifying an access group. Verify that
        // a token saved in the app's stable simulator group remains readable.
        var readQuery = query
        readQuery.removeValue(forKey: kSecAttrAccessGroup as String)
        readQuery[kSecReturnData as String] = true
        var result: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(readQuery as CFDictionary, &result), errSecSuccess)
        XCTAssertEqual(result as? Data, value)
    }
}
#endif
