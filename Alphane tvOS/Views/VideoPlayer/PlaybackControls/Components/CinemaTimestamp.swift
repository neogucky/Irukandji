//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    struct CinemaTimestamp: View {

        @Environment(ViewState.self)
        private var viewState
        @EnvironmentObject
        private var manager: MediaPlayerManager
        @EnvironmentObject
        private var scrubbedSecondsBox: PublishedBox<Duration>

        @State
        private var elapsedSize: CGSize = .zero
        @State
        private var remainingSize: CGSize = .zero

        private var progress: Double {
            guard let runtime = manager.item.runtime, runtime > .zero else { return 0 }

            return scrubbedSecondsBox.value / runtime
        }

        var body: some View {
            GeometryReader { geometry in
                let elapsedOffset = CinemaTimestampLayout.elapsedOffset(
                    progress: progress,
                    trackWidth: geometry.size.width,
                    labelWidth: elapsedSize.width
                )

                ZStack(alignment: .leading) {
                    HStack(spacing: 8) {
                        Text(scrubbedSecondsBox.value, format: .runtime)

                        if manager.playbackRequestStatus == .paused {
                            Image(systemName: "pause.circle")
                                .accessibilityHidden(true)
                        }
                    }
                    .fixedSize()
                    .trackingSize($elapsedSize)
                    .offset(x: elapsedOffset)

                    Group {
                        if let runtime = manager.item.runtime {
                            Text(.zero - max(.zero, runtime - scrubbedSecondsBox.value), format: .runtime)
                        } else {
                            Text(verbatim: .emptyRuntime)
                        }
                    }
                    .fixedSize()
                    .trackingSize($remainingSize)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .isVisible(CinemaTimestampLayout.showsRemainingTime(
                        elapsedOffset: elapsedOffset,
                        elapsedWidth: elapsedSize.width,
                        remainingWidth: remainingSize.width,
                        trackWidth: geometry.size.width
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 28)
            .font(.system(size: 22, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(viewState.isProgressBarFocused ? Color.white : AlphaneTheme.secondaryText)
        }
    }

    enum CinemaTimestampLayout {

        /// Center the elapsed time under the playhead, keeping it within the track edges.
        static func elapsedOffset(progress: Double, trackWidth: CGFloat, labelWidth: CGFloat) -> CGFloat {
            guard trackWidth.isFinite, labelWidth.isFinite, trackWidth > 0, labelWidth >= 0 else { return 0 }

            let progress = progress.isFinite ? clamp(progress, min: 0, max: 1) : 0
            return clamp(
                trackWidth * progress - labelWidth / 2,
                min: 0,
                max: max(0, trackWidth - labelWidth)
            )
        }

        /// Near the end, leave the moving timestamp readable instead of overlapping the countdown.
        static func showsRemainingTime(
            elapsedOffset: CGFloat,
            elapsedWidth: CGFloat,
            remainingWidth: CGFloat,
            trackWidth: CGFloat
        ) -> Bool {
            guard elapsedOffset.isFinite, elapsedWidth.isFinite, remainingWidth.isFinite, trackWidth.isFinite,
                  elapsedWidth > 0, remainingWidth > 0, trackWidth > 0
            else { return false }

            return elapsedOffset + elapsedWidth + 16 <= trackWidth - remainingWidth
        }
    }
}
