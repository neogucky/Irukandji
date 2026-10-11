//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension VideoPlayer.PlaybackControls {

    /// The side groups occupy equal space so transport stays centered on the screen.
    private var cinemaTransport: some View {
        HStack(spacing: 24) {
            if !manager.item.isLiveStream {
                Button(action: jumpBackward) {
                    Image(systemName: jumpBackwardInterval.secondarySystemImage)
                        .font(.system(size: 28, weight: .medium))
                        .frame(width: 76, height: 70)
                }
                .accessibilityLabel(L10n.jumpBackward)
                .accessibilityValue(jumpBackwardInterval.displayTitle)
                .coordinatedFocus(ViewState.Focus.action("jumpBackward"))
            }

            Button {
                manager.togglePlayPause()
                viewState.refreshAutoDismiss()
            } label: {
                Label(
                    manager.playbackRequestStatus == .paused ? L10n.resume : L10n.pause,
                    systemImage: manager.playbackRequestStatus == .paused ? "play.fill" : "pause.fill"
                )
                .font(.system(size: 24, weight: .semibold))
                .frame(width: 176, height: 70)
            }
            .coordinatedFocus(ViewState.Focus.action("playPause"))

            if !manager.item.isLiveStream {
                Button(action: jumpForward) {
                    Image(systemName: jumpForwardInterval.systemImage)
                        .font(.system(size: 28, weight: .medium))
                        .frame(width: 76, height: 70)
                }
                .accessibilityLabel(L10n.jumpForward)
                .accessibilityValue(jumpForwardInterval.displayTitle)
                .coordinatedFocus(ViewState.Focus.action("jumpForward"))
            }
        }
        .focusSection()
    }

    var cinemaControls: some View {
        HStack(spacing: 24) {
            HStack {
                if let queue = manager.queue,
                   viewState.supplements.contains(where: { $0.id == queue.id }) {
                    Button {
                        viewState.selectedSupplementID = queue.id
                    } label: {
                        Label(
                            manager.item.type == .episode ? L10n.episodes : queue.displayTitle,
                            systemImage: "rectangle.stack"
                        )
                        .font(.system(size: 22, weight: .medium))
                        .padding(.horizontal, 20)
                        .frame(height: 70)
                    }
                    .coordinatedFocus(ViewState.Focus.action("episodes"))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .focusSection()

            cinemaTransport

            Toolbar.ActionButtons()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(CinemaButtonStyle())
        .menuStyle(CinemaMenuStyle())
    }

    struct CinemaButtonStyle: ButtonStyle {

        @Environment(\.isFocused) private var isFocused
        @Environment(\.isEnabled) private var isEnabled
        @Environment(ViewState.self) private var viewState
        @State private var interactionID = UUID()

        var isMenu = false

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(isFocused ? Color.white : IrukandjiTheme.secondaryText)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(IrukandjiTheme.surface.opacity(isFocused ? 0.9 : 0))
                }
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .tvFocusBorder(isFocused: isFocused && isEnabled, shape: RoundedRectangle(cornerRadius: 16))
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.5)
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
                configuration.icon.font(.system(size: 24, weight: .medium))
                configuration.title.font(.system(size: 18, weight: .medium))
            }
            .lineLimit(1)
            .frame(width: 100, height: 70)
        }
    }
}
