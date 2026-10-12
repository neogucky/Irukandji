//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

/// Two stable positions, with the last playback action retained across the info transition.
struct TVDetailNavigation {

    enum Section: Equatable {
        case playback
        case info
    }

    private(set) var section: Section = .playback
    private(set) var isEnteringInfo = false
    private(set) var rememberedFocusID: String?
    private(set) var pendingPlaybackFocusID: String?

    mutating func rememberFocus(_ focusedIDs: Set<String>, validPlaybackIDs: Set<String>) {
        guard section == .playback else { return }

        let candidates = focusedIDs.intersection(validPlaybackIDs)
        if candidates.count == 1 {
            rememberedFocusID = candidates.first
        }
    }

    mutating func showInfo(hasInfo: Bool) {
        guard hasInfo, section == .playback else { return }

        section = .info
        isEnteringInfo = true
        pendingPlaybackFocusID = nil
    }

    mutating func infoDidReceiveFocus() {
        guard section == .info else { return }

        isEnteringInfo = false
    }

    mutating func showPlayback(validPlaybackIDs: Set<String>, preferredFocusID: String) {
        guard section == .info, !isEnteringInfo else { return }

        pendingPlaybackFocusID = rememberedFocusID.flatMap {
            validPlaybackIDs.contains($0) ? $0 : nil
        } ?? preferredFocusID
        section = .playback
    }

    mutating func playbackDidReceiveFocus(_ focusedIDs: Set<String>) {
        guard let pendingPlaybackFocusID, focusedIDs.contains(pendingPlaybackFocusID) else { return }

        self.pendingPlaybackFocusID = nil
    }
}
