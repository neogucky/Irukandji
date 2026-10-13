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
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero, diagnostics: { _ in nil })
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
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero, diagnostics: { _ in nil })
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
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .milliseconds(80), diagnostics: { _ in nil })
        let start = ContinuousClock.now
        await recovery.retry(error: URLError(.cannotConnectToHost)) {
            XCTAssertTrue(recovery.isRetrying)
            return URLError(.cannotConnectToHost)
        }
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(80))
        XCTAssertEqual(recovery.failedAttempts, 1)
    }

    func testFastSuccessAlsoKeepsTheBusyPresentationForTheMinimumDuration() async {
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .milliseconds(80), diagnostics: { _ in
            XCTFail("Successful requests must not run diagnostics")
            return nil
        })
        let start = ContinuousClock.now
        await recovery.retry(error: URLError(.cannotConnectToHost)) { nil }
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .milliseconds(80))
        XCTAssertNil(recovery.error)
        XCTAssertFalse(recovery.isRetrying)
    }

    func testDefaultRetryPresentationLastsTwoSeconds() async {
        let recovery = ErrorRecoveryState(diagnostics: { _ in nil })
        let start = ContinuousClock.now
        await recovery.retry(error: URLError(.cannotConnectToHost)) { nil }
        XCTAssertGreaterThanOrEqual(start.duration(to: .now), .seconds(2))
    }

    func testRetryRemainsBusyUntilLongerRequestAndDiagnosticsComplete() async throws {
        var pending: CheckedContinuation<ConnectionIssue?, Never>?
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .milliseconds(20), diagnostics: { _ in
            await withCheckedContinuation { pending = $0 }
        })
        let task = Task {
            await recovery.retry(error: URLError(.cannotConnectToHost)) {
                try? await Task.sleep(for: .milliseconds(40))
                return URLError(.cannotConnectToHost)
            }
        }
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(recovery.isRetrying)
        try XCTUnwrap(pending).resume(returning: .server)
        await task.value
        XCTAssertEqual(recovery.connectionIssue, .server)
        XCTAssertFalse(recovery.isRetrying)
    }

    func testOlderDiagnosisCannotReplaceTheResultOfANewerRetry() async throws {
        var old: CheckedContinuation<ConnectionIssue?, Never>?
        var calls = 0
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero, diagnostics: { _ in
            calls += 1
            if calls == 1 {
                return await withCheckedContinuation { old = $0 }
            }
            return .server
        })
        let diagnosis = Task { await recovery.diagnose(error: URLError(.cannotConnectToHost)) }
        for _ in 0 ..< 100 where old == nil {
            await Task.yield()
        }
        let continuation = try XCTUnwrap(old)
        await recovery.retry(error: URLError(.cannotConnectToHost)) { URLError(.cannotConnectToHost) }
        continuation.resume(returning: .network)
        await diagnosis.value
        XCTAssertEqual(recovery.connectionIssue, .server)
        XCTAssertFalse(recovery.isDiagnosing)
    }

    func testCancellingRetryDoesNotPublishAnObsoleteDiagnostic() async {
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .seconds(2), diagnostics: { _ in .server })
        let task = Task {
            await recovery.retry(error: URLError(.cannotConnectToHost)) { URLError(.cannotConnectToHost) }
        }
        await Task.yield()
        task.cancel()
        await task.value
        XCTAssertFalse(recovery.isRetrying)
        XCTAssertNil(recovery.connectionIssue)
    }

    func testRetryKeepsExistingDiagnosisWhileBusyAndDoesNotProbeTheSameOutcomeTwice() async {
        var probes = 0
        let recovery = ErrorRecoveryState(minimumFeedbackDuration: .zero, diagnostics: { _ in
            probes += 1
            return .server
        })
        let initial = URLError(.cannotConnectToHost)
        let next = URLError(.timedOut)
        await recovery.diagnose(error: initial)
        await recovery.retry(error: initial) {
            XCTAssertEqual(recovery.connectionIssue, .server)
            return next
        }
        await recovery.diagnose(error: next)
        XCTAssertEqual(probes, 2)
        XCTAssertEqual(recovery.connectionIssue, .server)
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
