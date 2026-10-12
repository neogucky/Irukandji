//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

enum TVSettingsText {
    static let on = String(localized: "On")
    static let off = String(localized: "Off")
}

/// Fixed geometry keeps the open settings columns still as focus moves.
struct TVSettingsButtonStyle: ButtonStyle {

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled

    var cutsOutLabel = true

    func makeBody(configuration: Configuration) -> some View {
        let hasFocus = isFocused && isEnabled
        return configuration.label
            .font(.system(size: 22, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(hasFocus ? Color.black : AlphaneTheme.secondaryText)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .fixedSize(horizontal: false, vertical: true)
            .blendMode(hasFocus && cutsOutLabel ? .destinationOut : .normal)
            .background {
                Capsule().fill(.white.opacity(hasFocus ? 1 : 0))
            }
            .compositingGroup()
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
            .animation(.easeOut(duration: 0.12), value: hasFocus)
    }
}

struct TVSettingsMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .menuStyle(.button)
            .buttonStyle(TVSettingsButtonStyle())
    }
}

struct TVSettingsRow: View {

    let title: String
    var value: String?
    var symbol: String? = "chevron.right"

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .font(.system(size: 20))
                    .lineLimit(1)
            }
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }
}

struct TVSettingsColumn<Content: View>: View {

    let title: String
    let symbol: String
    var showsTitle = true
    @ViewBuilder
    var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsTitle {
                Label(title, systemImage: symbol)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AlphaneTheme.secondaryText)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
                    .accessibilityAddTraits(.isHeader)
            }
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
    }
}

struct TVSettingsPage<Content: View>: View {

    let title: String
    @ViewBuilder
    var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                Text(title)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(60)
        }
        .buttonStyle(TVSettingsButtonStyle())
        .menuStyle(TVSettingsMenuStyle())
        .background(AlphaneTheme.background.ignoresSafeArea())
        .navigationTitle(title)
        .toolbar(.hidden, for: .navigationBar)
    }
}
