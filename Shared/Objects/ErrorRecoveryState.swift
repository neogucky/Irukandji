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

    private let minimumFeedbackDuration: Duration

    init(minimumFeedbackDuration: Duration = .milliseconds(600)) {
        self.minimumFeedbackDuration = minimumFeedbackDuration
    }

    func retry(error: Error, operation: @MainActor () async -> Error?) async {
        guard !isRetrying else { return }

        self.error = error
        isRetrying = true
        defer { isRetrying = false }

        let start = ContinuousClock.now
        let failure = await operation()

        // An immediate connection refusal still needs perceptible feedback.
        // Start the request immediately; only hold the failed presentation.
        if failure != nil {
            let elapsed = start.duration(to: .now)
            if elapsed < minimumFeedbackDuration {
                try? await Task.sleep(for: minimumFeedbackDuration - elapsed)
            }
        }
        guard !Task.isCancelled else { return }

        self.error = failure
        failedAttempts = failure == nil ? 0 : failedAttempts + 1
    }
}
