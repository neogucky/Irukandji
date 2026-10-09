//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

enum PlaybackCompletion {

    static func reachedEnd(of item: BaseItemDto, at positionTicks: Int?) -> Bool {
        guard let runtime = item.runTimeTicks, runtime > 0,
              let positionTicks, positionTicks > 0
        else { return false }
        return positionTicks >= runtime - 10_000_000
    }

    @MainActor
    static func refreshedItem(
        stoppedAt positionTicks: Int?,
        fetch: () async throws -> BaseItemDto,
        pause: () async throws -> Void = { try await Task.sleep(for: .milliseconds(500)) }
    ) async throws -> BaseItemDto {
        var item = try await fetch()
        guard reachedEnd(of: item, at: positionTicks) else { return item }

        for _ in 0..<3 {
            if item.userData?.isPlayed == true { return item }
            try await pause()
            item = try await fetch()
        }

        // A natural ending is known locally even if a read replica or cache
        // still has the older resume point. This affects display only.
        item.userData?.isPlayed = true
        item.userData?.playbackPositionTicks = 0
        item.userData?.playedPercentage = 100
        return item
    }
}
