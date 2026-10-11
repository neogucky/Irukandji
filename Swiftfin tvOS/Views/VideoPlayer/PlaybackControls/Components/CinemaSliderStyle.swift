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

    @Environment(\.displayScale)
    private var displayScale

    func makeBody(configuration: SliderContainerStyleConfiguration) -> some View {
        GeometryReader { geometry in
            let progress = configuration.progress
            let origin = configuration.originProgress
            let committed = min(progress, origin ?? progress)
            let playheadSize: CGFloat = configuration.isFocused ? 18 : 12
            let trackHeight: CGFloat = 4

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))

                if let origin {
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: geometry.size.width * max(progress, origin))
                }

                Capsule()
                    .fill(IrukandjiTheme.accent)
                    .frame(width: geometry.size.width * committed)
            }
            .frame(height: trackHeight)
            .tvFocusBorder(isFocused: configuration.isFocused, shape: Capsule(), lineWidth: 1 / displayScale)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(configuration.isFocused ? Color.white : IrukandjiTheme.secondaryText)
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
