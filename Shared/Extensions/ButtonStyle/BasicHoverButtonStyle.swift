//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

#if os(tvOS)
struct BasicHoverButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tvFocusBorder(isFocused: isFocused && isEnabled, shape: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : (isFocused ? 1 : 0.8)) : 0.5)
    }
}
#else
typealias BasicHoverButtonStyle = BorderlessButtonStyle
#endif
