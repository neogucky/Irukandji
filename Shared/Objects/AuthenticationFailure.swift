//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI

enum AuthenticationFailure {

    static let message = String(localized: "Your sign-in is no longer valid.")
    static let suggestion = String(localized: "Retry, or sign out to enter your password again.")

    /// Inspect typed SDK errors and their underlying causes. A 403 may simply
    /// mean this user lacks permission; it must not invalidate their sign-in.
    static func isUnauthorized(_ error: Error) -> Bool {
        var current = error
        for _ in 0 ..< 8 {
            if let error = current as? APIError, case .unacceptableStatusCode(401) = error {
                return true
            }
            if let error = current as? JellyfinSocket.Session.SocketError {
                switch error {
                case .unauthorized(statusCode: 401): return true

                case let .reconnectAttemptsReached(underlying?):
                    current = underlying
                    continue

                default: break
                }
            }
            let failure = current as NSError
            if failure.domain == NSURLErrorDomain, failure.code == URLError.userAuthenticationRequired.rawValue {
                return true
            }
            guard let underlying = failure.userInfo[NSUnderlyingErrorKey] as? Error else { return false }

            current = underlying
        }
        return false
    }
}
