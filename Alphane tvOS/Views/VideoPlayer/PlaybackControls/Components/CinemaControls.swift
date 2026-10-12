//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    var cinemaControls: some View {
        HStack(spacing: 20) {
            if let queue = manager.queue,
               viewState.supplements.contains(where: { $0.id == queue.id })
            {
                Button {
                    viewState.selectedSupplementID = queue.id
                } label: {
                    Label(
                        manager.item.type == .episode ? L10n.episodes : queue.displayTitle,
                        systemImage: "rectangle.stack"
                    )
                }
                .labelStyle(CinemaActionLabelStyle())
                .coordinatedFocus(ViewState.Focus.action("episodes"))
            }

            Toolbar.ActionButtons()
        }
        .focusSection()
        .buttonStyle(CinemaButtonStyle())
        .menuStyle(CinemaMenuStyle())
    }

    struct CinemaButtonStyle: ButtonStyle {

        @Environment(\.isFocused)
        private var isFocused
        @Environment(\.isEnabled)
        private var isEnabled
        @Environment(ViewState.self)
        private var viewState
        @State
        private var interactionID = UUID()

        var isMenu = false

        func makeBody(configuration: Configuration) -> some View {
            let hasFocus = isFocused && isEnabled
            let isActive = hasFocus || (isMenu && configuration.isPressed)

            return ZStack {
                Capsule()
                    .fill(.white.opacity(hasFocus ? 1 : (isActive ? 0.8 : 0)))

                configuration.label
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isActive ? Color.black : AlphaneTheme.secondaryText)
                    .blendMode(isActive ? .destinationOut : .normal)
            }
            .fixedSize()
            .compositingGroup()
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
            .animation(.easeOut(duration: 0.12), value: hasFocus)
            .onChange(of: configuration.isPressed) {
                viewState.setInteraction(interaction, active: configuration.isPressed)
            }
            .onDisappear {
                viewState.setInteraction(interaction, active: false)
            }
        }

        private var interaction: ViewState.Interaction {
            isMenu ? .menu(interactionID) : .button(interactionID)
        }
    }

    struct CinemaMenuStyle: MenuStyle {
        func makeBody(configuration: Configuration) -> some View {
            Menu(configuration)
                .menuStyle(.button)
                .buttonStyle(CinemaButtonStyle(isMenu: true))
                .symbolRenderingMode(.monochrome)
        }
    }

    struct CinemaActionLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(spacing: 6) {
                configuration.icon
                    .font(.system(size: 24, weight: .medium))
                    .frame(height: 30)
                configuration.title
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 24)
            }
            .lineLimit(1)
            .frame(width: 120, height: 80)
        }
    }
}
