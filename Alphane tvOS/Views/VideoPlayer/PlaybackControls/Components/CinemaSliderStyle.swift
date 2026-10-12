//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

/// A constant-sized focus target with a slim track and an always-visible playhead.
struct CinemaSliderStyle: SliderContainerStyle {

    func makeBody(configuration: SliderContainerStyleConfiguration) -> some View {
        GeometryReader { geometry in
            let progress = configuration.progress
            let origin = configuration.originProgress
            let committed = min(progress, origin ?? progress)
            let playheadSize: CGFloat = 16
            let trackHeight: CGFloat = 4
            let accent = AlphaneTheme.accent

            ZStack(alignment: .leading) {
                Capsule().fill(accent.opacity(configuration.isFocused ? 0.4 : 0.16))

                if let origin {
                    Capsule()
                        .fill(accent.opacity(configuration.isFocused ? 0.6 : 0.3))
                        .frame(width: geometry.size.width * max(progress, origin))
                }

                Capsule()
                    .fill(accent.opacity(configuration.isFocused ? 1 : 0.45))
                    .frame(width: geometry.size.width * committed)
            }
            .frame(height: trackHeight)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(configuration.isFocused ? Color.white : AlphaneTheme.secondaryText)
                    .frame(width: playheadSize, height: playheadSize)
                    .offset(x: clamp(
                        geometry.size.width * progress - playheadSize / 2,
                        min: 0,
                        max: max(0, geometry.size.width - playheadSize)
                    ))
            }
            .frame(maxHeight: .infinity)
        }
    }
}
