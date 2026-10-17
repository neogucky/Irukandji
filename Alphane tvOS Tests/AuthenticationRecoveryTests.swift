//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import Combine
import Defaults
import FactoryKit
import Foundation
import Get
import JellyfinAPI
import KeychainSwift
import Security
import XCTest

@MainActor
final class AuthenticationRecoveryTests: XCTestCase {

    func testRecognizesHTTPAndSocketAuthenticationFailuresIncludingUnderlyingErrors() {
        let failures: [Error] = [
            APIError.unacceptableStatusCode(401),
            JellyfinSocket.Session.SocketError.unauthorized(statusCode: 401),
            JellyfinSocket.Session.SocketError.reconnectAttemptsReached(APIError.unacceptableStatusCode(401)),
            URLError(.userAuthenticationRequired),
            NSError(domain: "Wrapped", code: 0, userInfo: [NSUnderlyingErrorKey: APIError.unacceptableStatusCode(401)])
        ]
        for error in failures {
            XCTAssertTrue(AuthenticationFailure.isUnauthorized(error), "\(error)")
        }
    }

    func testPermissionsTransportAndUnrelatedErrorCodesDoNotInvalidateAuthentication() {
        let failures: [Error] = [
            APIError.unacceptableStatusCode(403),
            APIError.unacceptableStatusCode(500),
            JellyfinSocket.Session.SocketError.unauthorized(statusCode: 403),
            JellyfinSocket.Session.SocketError.reconnectAttemptsReached(URLError(.timedOut)),
            URLError(.notConnectedToInternet),
            NSError(domain: "Unrelated", code: 401),
            ErrorMessage("401")
        ]
        for error in failures {
            XCTAssertFalse(AuthenticationFailure.isUnauthorized(error), "\(error)")
        }
    }

    func testRetryKeepsCredentialsAndCanRecoverWithoutSigningOut() async throws {
        try await withProfile { fixture in
            let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero, diagnostics: { _ in nil })
            await recovery.retry(error: APIError.unacceptableStatusCode(401)) {
                APIError.unacceptableStatusCode(401)
            }
            XCTAssertTrue(try AuthenticationFailure.isUnauthorized(XCTUnwrap(recovery.error)))
            XCTAssertEqual(fixture.user.accessToken, "expired-test-token")
            try await recovery.retry(error: XCTUnwrap(recovery.error)) { nil }
            XCTAssertNil(recovery.error)
            XCTAssertEqual(fixture.user.accessToken, "expired-test-token")
            XCTAssertFalse(fixture.user.requiresServerSignIn)
        }
    }

    func testExplicitAuthenticationSignOutForgetsOnlyThatTokenAndEndsTheSession() async throws {
        try await withProfile { fixture in
            try await fixture.manager.signIn(userID: fixture.user.id)
            let session = try XCTUnwrap(fixture.manager.currentSession)
            try await fixture.manager.signOutRequiringAuthentication(for: session)

            XCTAssertNil(fixture.manager.currentSession)
            XCTAssertEqual(fixture.manager.state, .signedOut)
            XCTAssertEqual(Defaults[.lastSignedInUserID].rawValue, "")
            XCTAssertTrue(fixture.user.requiresServerSignIn)
            XCTAssertNil(fixture.keychain.get("\(fixture.user.id)-accessToken"))
            XCTAssertEqual(fixture.otherUser.accessToken, "other-test-token")
            XCTAssertEqual(StoredValues[.User.users], [fixture.user, fixture.otherUser])
            XCTAssertEqual(StoredValues[.Server.servers], [fixture.server])
            XCTAssertEqual(fixture.user.pin, "1234")
            XCTAssertEqual(fixture.user.pinHint, "Test hint")
            XCTAssertEqual(fixture.user.accessPolicy, .requirePin)
            XCTAssertEqual(fixture.user.data.name, "Saved profile")
        }
    }

    func testOrdinaryLogoutStillKeepsTheSavedSignIn() async throws {
        try await withProfile { fixture in
            try await fixture.manager.signIn(userID: fixture.user.id)
            await fixture.manager.signOut(reason: .explicit)
            XCTAssertNil(fixture.manager.currentSession)
            XCTAssertEqual(fixture.user.accessToken, "expired-test-token")
            XCTAssertFalse(fixture.user.requiresServerSignIn)
            try await fixture.manager.signIn(userID: fixture.user.id)
            XCTAssertEqual(fixture.manager.currentSession?.user, fixture.user)
        }
    }

    func testForgottenCredentialsCannotBeUsedByProfileSelectionOrDeepLinks() async throws {
        try await withProfile { fixture in
            try fixture.user.forgetAccessToken()
            do {
                try await fixture.manager.signIn(userID: fixture.user.id)
                XCTFail("A retained profile must require fresh server authentication")
            } catch let UserSessionError.serverAuthenticationRequired(userID) {
                XCTAssertEqual(userID, fixture.user.id)
            }
            XCTAssertNil(fixture.manager.currentSession)
            XCTAssertEqual(Defaults[.lastSignedInUserID].rawValue, "")

            let url = try XCTUnwrap(URL(string: "alphane://\(fixture.server.id)/\(fixture.user.id)/item/test-item"))
            await fixture.manager.handleOpenURL(url, authenticationAction: .init { _, _ in
                PinEvaluatedUserAccessPolicy(pin: "1234", pinHint: nil)
            })
            XCTAssertNil(fixture.manager.currentSession)
            XCTAssertNil(fixture.manager.pendingDeepLink)
        }
    }

    func testLaunchCannotRestoreAProfileWhoseCredentialsWereForgotten() async throws {
        try await withProfile { fixture in
            try fixture.user.forgetAccessToken()
            Defaults[.lastSignedInUserID] = .signedIn(userID: fixture.user.id)
            await fixture.manager.start()
            XCTAssertEqual(fixture.manager.state, .signedOut)
            XCTAssertNil(fixture.manager.currentSession)
            XCTAssertEqual(Defaults[.lastSignedInUserID].rawValue, "")
        }
    }

    func testAnErrorFromAnOlderSessionCannotSignOutTheCurrentUser() async throws {
        try await withProfile { fixture in
            try await fixture.manager.signIn(userID: fixture.user.id)
            let previous = try XCTUnwrap(fixture.manager.currentSession)
            try await fixture.manager.signIn(userID: fixture.otherUser.id)
            let current = fixture.manager.currentSession
            try await fixture.manager.signOutRequiringAuthentication(for: previous)
            XCTAssertTrue(fixture.manager.currentSession === current)
            XCTAssertEqual(fixture.user.accessToken, "expired-test-token")
            XCTAssertEqual(fixture.otherUser.accessToken, "other-test-token")
        }
    }

    func testKeychainFailureDoesNotPretendToHaveSignedOutAndForgottenCredentials() async throws {
        try await withProfile { fixture in
            try await fixture.manager.signIn(userID: fixture.user.id)
            let session = try XCTUnwrap(fixture.manager.currentSession)
            fixture.keychain.failDeletion = true
            do {
                try await fixture.manager.signOutRequiringAuthentication(for: session)
                XCTFail("The failure must be shown so the user knows credentials were not cleared")
            } catch {
                XCTAssertTrue(fixture.manager.currentSession === session)
                XCTAssertFalse(fixture.user.requiresServerSignIn)
            }
        }
    }

    func testForgettingAnAlreadyMissingTokenIsSafe() async throws {
        try await withProfile { fixture in
            try fixture.user.forgetAccessToken()
            try fixture.user.forgetAccessToken()
            XCTAssertTrue(fixture.user.requiresServerSignIn)
        }
    }

    func testReauthenticationReplacesTheTokenWithoutDuplicatingTheProfileOrResettingItsPIN() async throws {
        try await withProfile { fixture in
            try fixture.user.forgetAccessToken()
            let model = UserSignInViewModel(server: fixture.server)
            var saved: UserState?
            let observation = model.events.sink { event in
                if case let .saved(user) = event {
                    saved = user
                }
            }
            defer { observation.cancel() }
            await model.saveExisting(
                user: ((fixture.user, "fresh-test-token"), UserDto(id: fixture.user.id, name: "Refreshed profile")),
                replaceForAccessToken: false,
                authenticationAction: (.init { policy, _ in
                    XCTAssertEqual(policy, .requirePin)
                    return PinEvaluatedUserAccessPolicy(pin: "1234", pinHint: nil)
                }, fixture.user.accessPolicy, nil),
                evaluatedPolicyMap: .init { $0 }
            )
            XCTAssertNil(model.error)
            XCTAssertEqual(saved, fixture.user)
            XCTAssertEqual(fixture.user.accessToken, "fresh-test-token")
            XCTAssertFalse(fixture.user.requiresServerSignIn)
            XCTAssertEqual(StoredValues[.User.users], [fixture.user, fixture.otherUser])
            XCTAssertEqual(fixture.user.pin, "1234")
            XCTAssertEqual(fixture.user.pinHint, "Test hint")
            XCTAssertEqual(fixture.user.accessPolicy, .requirePin)
            XCTAssertEqual(fixture.user.data.name, "Refreshed profile")
        }
    }

    func testIncorrectLocalPINCannotReplaceTheForgottenToken() async throws {
        try await withProfile { fixture in
            try fixture.user.forgetAccessToken()
            let model = UserSignInViewModel(server: fixture.server)
            await model.saveExisting(
                user: ((fixture.user, "fresh-test-token"), UserDto(id: fixture.user.id)),
                replaceForAccessToken: true,
                authenticationAction: (.init { _, _ in
                    PinEvaluatedUserAccessPolicy(pin: "9999", pinHint: nil)
                }, .requirePin, nil),
                evaluatedPolicyMap: .init { $0 }
            )
            XCTAssertNotNil(model.error)
            XCTAssertTrue(fixture.user.requiresServerSignIn)
            XCTAssertEqual(fixture.user.pin, "1234")
        }
    }

    func testRejectedPasswordDoesNotRestoreOrSaveCredentials() async throws {
        try await withProfile { fixture in
            try fixture.user.forgetAccessToken()
            let model = UserSignInViewModel(server: fixture.server)
            var receivedEvent = false
            let observation = model.events.sink { _ in receivedEvent = true }
            defer { observation.cancel() }
            await model.signIn(username: fixture.user.username, password: "wrong-test-password")
            XCTAssertTrue(try AuthenticationFailure.isUnauthorized(XCTUnwrap(model.error)))
            XCTAssertTrue(fixture.user.requiresServerSignIn)
            XCTAssertFalse(receivedEvent)
            XCTAssertEqual(StoredValues[.User.users], [fixture.user, fixture.otherUser])
        }
    }

    private struct Fixture {
        let user: UserState
        let otherUser: UserState
        let server: ServerState
        let keychain: TestKeychain
        let manager: UserSessionManager
    }

    /// Every test uses disposable credentials and restores the simulator's saved
    /// profiles and defaults. No request is sent to the user's Jellyfin server.
    private func withProfile(_ body: (Fixture) async throws -> Void) async throws {
        let users = StoredValues[.User.users]
        let servers = StoredValues[.Server.servers]
        let lastUser = Defaults[.lastSignedInUserID]
        let signOutOnClose = Defaults[.signOutOnClose]
        let configuration = URLSessionConfiguration.alphane
        let protocolClasses = configuration.protocolClasses
        let id = UUID().uuidString
        let user = UserState(id: "user-\(id)", serverID: "server-\(id)", username: "Saved profile")
        let otherUser = UserState(id: "other-\(id)", serverID: user.serverID, username: "Other profile")
        let url = try XCTUnwrap(URL(string: "https://authentication-test.invalid"))
        let server = ServerState(urls: [url], currentURL: url, name: "Test server", id: user.serverID, userIDs: [user.id, otherUser.id])
        let keychain = TestKeychain(keyPrefix: "authentication-tests-\(id)-")
        Container.shared.keychainService.register { keychain }
        configuration.protocolClasses = [UnauthorizedProtocol.self]
        defer {
            keychain.failDeletion = false
            for profile in [user, otherUser] {
                keychain.delete("\(profile.id)-accessToken")
                keychain.delete("\(profile.id)-pin")
                UserDefaults.userSuite(id: profile.id).removeAll()
            }
            UserDefaults.userSuite(id: server.id).removeAll()
            Container.shared.keychainService.reset()
            configuration.protocolClasses = protocolClasses
            StoredValues[.User.users] = users
            StoredValues[.Server.servers] = servers
            Defaults[.lastSignedInUserID] = lastUser
            Defaults[.signOutOnClose] = signOutOnClose
        }
        StoredValues[.User.users] = [user, otherUser]
        StoredValues[.Server.servers] = [server]
        Defaults[.lastSignedInUserID] = .signedOut
        Defaults[.signOutOnClose] = false
        user.accessToken = "expired-test-token"
        otherUser.accessToken = "other-test-token"
        user.pin = "1234"
        user.pinHint = "Test hint"
        user.accessPolicy = .requirePin
        user.data = UserDto(id: user.id, name: "Saved profile")
        let manager = UserSessionManager()
        do {
            try await body(Fixture(user: user, otherUser: otherUser, server: server, keychain: keychain, manager: manager))
        } catch {
            await manager.signOut(reason: .explicit)
            throw error
        }
        await manager.signOut(reason: .explicit)
    }
}

private final class TestKeychain: KeychainSwift {
    var failDeletion = false

    override func delete(_ key: String) -> Bool {
        if failDeletion {
            lastResultCode = errSecAuthFailed
            return false
        }
        return super.delete(key)
    }
}

private final class UnauthorizedProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
