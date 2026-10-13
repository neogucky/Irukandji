//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

/// Keeps the error presentation stable while the underlying page reloads.
@MainActor
final class ErrorRecoveryState: ObservableObject {

    @Published
    private(set) var isRetrying = false
    @Published
    private(set) var error: Error?
    @Published
    private(set) var failedAttempts = 0
    @Published
    private(set) var connectionIssue: ConnectionIssue?
    @Published
    private(set) var isDiagnosing = false

    private let minimumFeedbackDuration: Duration
    private let diagnostics: @MainActor (Error) async -> ConnectionIssue?
    private var diagnosticID: UUID?
    private var diagnosedErrorID: String?

    init(
        minimumFeedbackDuration: Duration = .seconds(2),
        diagnostics: @escaping @MainActor (Error) async -> ConnectionIssue? = { await ConnectionDiagnostics.diagnose($0) }
    ) {
        self.minimumFeedbackDuration = minimumFeedbackDuration
        self.diagnostics = diagnostics
    }

    func diagnose(error: Error) async {
        let errorID = ConnectionDiagnostics.failureID(for: error)
        guard !isRetrying, diagnosedErrorID != errorID else { return }

        let id = UUID()
        diagnosticID = id
        connectionIssue = nil
        isDiagnosing = ConnectionDiagnostics.connectionError(in: error) != nil
        let issue = await diagnostics(error)
        guard diagnosticID == id else { return }

        isDiagnosing = false
        guard !Task.isCancelled else { return }

        diagnosedErrorID = errorID
        connectionIssue = issue
    }

    func retry(error: Error, operation: @MainActor () async -> Error?) async {
        guard !isRetrying else { return }

        self.error = error
        diagnosticID = nil
        isDiagnosing = false
        isRetrying = true
        defer { isRetrying = false }

        let start = ContinuousClock.now
        let failure = await operation()
        let issue: ConnectionIssue? = if let failure, !Task.isCancelled {
            await diagnostics(failure)
        } else {
            nil
        }

        // Start the request immediately, then keep its spinner visible for at
        // least two seconds, including when the retry succeeds quickly.
        let elapsed = start.duration(to: .now)
        if elapsed < minimumFeedbackDuration {
            try? await Task.sleep(for: minimumFeedbackDuration - elapsed)
        }
        guard !Task.isCancelled else { return }

        self.error = failure
        diagnosedErrorID = failure.map(ConnectionDiagnostics.failureID)
        connectionIssue = issue
        failedAttempts = failure == nil ? 0 : failedAttempts + 1
    }
}
