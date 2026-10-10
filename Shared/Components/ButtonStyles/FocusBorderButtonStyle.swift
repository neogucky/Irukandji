//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension View {

    /// Draw outside the existing bounds without changing the layout or hit target.
    @ViewBuilder
    func tvFocusBorder(isFocused: Bool, shape: some InsettableShape) -> some View {
        #if os(tvOS)
        overlay {
            shape
                .inset(by: -3)
                .stroke(.white, lineWidth: 6)
                .shadow(color: .black.opacity(0.8), radius: 2)
                .opacity(isFocused ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isFocused)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #else
        self
        #endif
    }
}

#if os(tvOS)
extension ButtonStyle where Self == FocusBorderButtonStyle<RoundedRectangle> {

    static var focusBorder: Self {
        FocusBorderButtonStyle(shape: RoundedRectangle(cornerRadius: 20))
    }
}

/// Replaces system focus enlargement without adding padding or a background.
struct FocusBorderButtonStyle<BorderShape: InsettableShape>: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled

    let shape: BorderShape

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tvFocusBorder(isFocused: isFocused && isEnabled, shape: shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Artwork buttons draw the border around their image rather than the caption.
struct ArtworkButtonStyle: ButtonStyle {

    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
