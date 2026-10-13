//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

@testable import Alphane
import Foundation
import XCTest

@MainActor
final class ErrorRecoveryTests: XCTestCase {

    func testFailedRequestCanBeRetriedAndSuccessfulRetryLeavesTheErrorPage() async {
        let provider = FailingProvider()
        let model = ContentGroupViewModel(provider: provider)
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero)
        await model.refresh()
        XCTAssertEqual(model.state, .error)

        await recovery.retry(error: URLError(.cannotConnectToHost)) {
            XCTAssertTrue(recovery.isRetrying)
            return await model.retryRefresh()
        }
        XCTAssertEqual(provider.requests, 2)
        XCTAssertEqual(model.state, .error)
        XCTAssertEqual(recovery.failedAttempts, 1)
        XCTAssertNotNil(recovery.error)
        XCTAssertFalse(recovery.isRetrying)

        provider.isOffline = false
        await recovery.retry(error: URLError(.cannotConnectToHost)) {
            await model.retryRefresh()
        }
        XCTAssertEqual(provider.requests, 3)
        XCTAssertEqual(model.state, .content)
        XCTAssertNil(model.error)
        XCTAssertNil(recovery.error)
        XCTAssertEqual(recovery.failedAttempts, 0)
        XCTAssertFalse(recovery.isRetrying)
    }

    func testRepeatedSelectWhileRetryingDoesNotStartAnotherRequest() async throws {
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero)
        let error = URLError(.cannotConnectToHost)
        var pending: CheckedContinuation<Error?, Never>?
        var requests = 0
        let task = Task {
            await recovery.retry(error: error) {
                requests += 1
                return await withCheckedContinuation { pending = $0 }
            }
        }
        for _ in 0 ..< 100 where pending == nil {
            await Task.yield()
        }
        let continuation = try XCTUnwrap(pending)
        XCTAssertTrue(recovery.isRetrying)
        XCTAssertNotNil(recovery.error)
        await recovery.retry(error: error) {
            requests += 1
            return nil
        }
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(recovery.isRetrying)
        continuation.resume(returning: error)
        await task.value
        XCTAssertFalse(recovery.isRetrying)
        XCTAssertEqual(recovery.failedAttempts, 1)
    }

    func testFastFailureRemainsVisibleWhileBusyFeedbackCompletes() async {
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .milliseconds(80))
        let start = ContinuousClock.now
        await recovery.retry(error: URLError(.cannotConnectToHost)) {
            XCTAssertTrue(recovery.isRetrying)
            return URLError(.cannotConnectToHost)
        }
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(80))
        XCTAssertEqual(recovery.failedAttempts, 1)
    }

    func testNetworkErrorsWithoutDescriptionsDoNotShowFrameworkErrorCodes() {
        for code: URLError.Code in [.cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost] {
            let message = ErrorView<URLError>.displayMessage(for: URLError(code))
            XCTAssertFalse(message.contains(NSURLErrorDomain))
            XCTAssertFalse(message.contains(String(code.rawValue)))
        }
    }

    func testNonNetworkErrorKeepsItsUsefulExplanation() {
        let error = ErrorMessage("This item is unavailable.")
        XCTAssertEqual(ErrorView<ErrorMessage>.displayMessage(for: error), error.localizedDescription)
    }

    private final class FailingProvider: ContentGroupProvider {
        let id = "connection-recovery-test"
        let displayTitle = "Connection recovery"
        var isOffline = true
        var requests = 0

        func makeGroups(environment: Empty) async throws -> [any ContentGroup] {
            requests += 1
            if isOffline {
                throw URLError(.cannotConnectToHost)
            }
            return []
        }
    }
}
