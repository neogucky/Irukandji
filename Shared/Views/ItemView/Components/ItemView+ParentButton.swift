//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension ItemView {

    struct ParentButton: View {

        @Router
        private var router

        let title: String
        let id: String

        var body: some View {
            Button {
                router.route(to: .item(id: id))
            } label: {
                Label {
                    Text(title)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "chevron.forward")
                        #if os(iOS)
                        .foregroundStyle(.secondary)
                        #endif
                }
            }
            .lineLimit(1)
            .labelStyle(.trailingIcon)
            #if os(tvOS)
            .buttonStyle(TVParentLinkButtonStyle())
            #else
            .foregroundStyle(.primary, .secondary)
            .buttonStyle(.capsule)
            #endif
            .controlSize(.regular)
        }
    }
}

#if os(tvOS)
/// Anchor the series label to the title; only the focus pill extends into the gutter.
private struct TVParentLinkButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let hasFocus = isEnabled && isFocused

        ZStack {
            Capsule()
                .fill(.white.opacity(hasFocus ? 0.8 : 0))
                .padding(.horizontal, -22)

            configuration.label
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(hasFocus ? Color.black : Color.white.opacity(0.8))
                .padding(.vertical, 5)
                .frame(minHeight: 30)
                .blendMode(hasFocus ? .destinationOut : .normal)
        }
        .fixedSize()
        .compositingGroup()
        .contentShape(.capsule)
        .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
        .animation(.easeOut(duration: 0.12), value: hasFocus)
    }
}
#endif
