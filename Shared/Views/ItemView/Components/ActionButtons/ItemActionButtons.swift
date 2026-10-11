//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

private struct ItemActionButtonLabelStyle: LabelStyle {

    @Environment(\.isSelected)
    private var isSelected
    @Environment(\.isFocused)
    private var isFocused

    var activeColor: Color?

    private var iconSize: CGFloat {
        UIDevice.isTV ? 40 : 24
    }

    private var tint: Color {
        #if os(tvOS)
        return AlphaneTheme.surface
        #else
        guard isSelected, let activeColor else {
            return .gray.opacity(0.15)
        }

        return activeColor
        #endif
    }

    private var foregroundColor: Color {
        #if os(tvOS)
        let color = isSelected ? activeColor ?? .white : .white
        return color.opacity(isFocused ? 1 : 0.8)
        #else
        guard isSelected, let activeColor else {
            return .primary
        }

        return activeColor.overlayColor
        #endif
    }

    func makeBody(configuration: Configuration) -> some View {
        #if os(tvOS)
        Label(configuration)
            .labelStyle(.iconOnly)
            .font(.system(size: 28, weight: .medium))
            .frame(width: 32, height: 36)
        #else
        Label(configuration)
            .labelStyle(.iconOnly)
            .font(UIDevice.isTV ? .system(size: 30) : .title3)
            .frame(width: iconSize, height: iconSize)
            .padding(UIDevice.isTV ? 16 : 8)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .backport
            .glassEffect(
                .regular.selection(
                    tint: tint,
                    foregroundColor: foregroundColor
                ),
                in: .capsule
            )
        #endif
    }
}

struct ItemActionButtons: View {

    static let maximumButtons = 4

    @ObservedObject
    var provider: ItemContentGroupProvider

    let buttons: [ItemActionButton]
    let overflowButtons: [ItemActionButton]
    let menuButtons: [ItemActionButton]
    let focusedButton: FocusState<String?>.Binding

    private static func hasTrailers(
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> Bool {
        if enabledTrailers.contains(.local), provider.localTrailers.isNotEmpty {
            return true
        }

        if enabledTrailers.contains(.external), provider.item.remoteTrailers?.isNotEmpty == true {
            return true
        }

        return false
    }

    private static func isAvailable(
        _ button: ItemActionButton,
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> Bool {
        switch button {
        case .played:
            provider.item.canBePlayed
        case .favorited:
            provider.item.canBeFavorited
        case .trailers:
            hasTrailers(for: provider, enabledTrailers: enabledTrailers)
        case .playback:
            provider.item.presentPlayButton && provider.mediaPlayerItemProvider?.mediaSource != nil
        case .record:
            provider.item.canBeRecorded
        case .refresh:
            provider.item.canEditMetadata
        case .subtitles:
            provider.item.canEditSubtitles
        case .delete:
            provider.item.canDelete == true
        #if os(iOS)
        case .editMetadata:
            provider.item.canEditMetadata
        #endif
        }
    }

    private static func availableButtons(
        _ buttons: [ItemActionButton],
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> [ItemActionButton] {
        buttons.filter {
            #if os(tvOS)
            // Keep server administration out of the watching flow. Subtitle management
            // lives with source and track selection in the playback menu.
            guard $0 != .delete, $0 != .refresh, $0 != .subtitles else { return false }
            #endif
            return isAvailable($0, for: provider, enabledTrailers: enabledTrailers)
        }
    }

    static func resolvedButtons(
        bar: [ItemActionButton],
        menu: [ItemActionButton],
        for provider: ItemContentGroupProvider,
        enabledTrailers: TrailerSelection
    ) -> (visible: [ItemActionButton], overflow: [ItemActionButton], menu: [ItemActionButton]) {
        #if os(tvOS)
        // The source/track control stays discoverable even with a customized action bar.
        var bar = availableButtons(bar.filter { $0 != .playback }, for: provider, enabledTrailers: enabledTrailers)
        if isAvailable(.playback, for: provider, enabledTrailers: enabledTrailers) {
            bar.insert(.playback, at: min(2, bar.count))
        }
        let menu = availableButtons(menu.filter { $0 != .playback }, for: provider, enabledTrailers: enabledTrailers)
        #else
        let bar = availableButtons(bar, for: provider, enabledTrailers: enabledTrailers)
        let menu = availableButtons(menu, for: provider, enabledTrailers: enabledTrailers)
        #endif

        let hasBarMenu = UIDevice.isTV && (menu.isNotEmpty || bar.count > maximumButtons)
        let visible = Array(bar.prefix(hasBarMenu ? maximumButtons - 1 : maximumButtons))
        let overflow = Array(bar.dropFirst(visible.count))

        return (
            visible: visible,
            overflow: overflow,
            menu: menu.subtracting(overflow)
        )
    }

    @ViewBuilder
    static func view(for button: ItemActionButton) -> some View {
        Group {
            switch button {
            case .played:
                Played()
            case .favorited:
                Favorited()
            case .trailers:
                Trailers()
            case .playback:
                Playback()
            case .record:
                Record()
            case .refresh:
                Refresh()
            case .subtitles:
                Subtitles()
            case .delete:
                Delete()
            #if os(iOS)
            case .editMetadata:
                Edit()
            #endif
            }
        }
        .symbolRenderingMode(.monochrome)
        .foregroundStyle(.primary, .secondary)
    }

    var body: some View {
        let hasBarMenu = UIDevice.isTV && (overflowButtons.isNotEmpty || menuButtons.isNotEmpty)

        if buttons.isNotEmpty || hasBarMenu {
            HStack(alignment: .center, spacing: UIDevice.isTV ? 24 : 8) {
                ForEach(buttons) { button in
                    #if os(tvOS)
                    if button == .played || button == .favorited {
                        Self.view(for: button)
                            .labelStyle(ItemActionButtonLabelStyle())
                            .buttonStyle(TVAccentItemActionButtonStyle())
                            .focused(focusedButton, equals: button.id)
                    } else {
                        Self.view(for: button)
                            .labelStyle(ItemActionButtonLabelStyle(activeColor: button.activeColor))
                            .focused(focusedButton, equals: button.id)
                    }
                    #else
                    Self.view(for: button)
                        .labelStyle(ItemActionButtonLabelStyle(activeColor: button.activeColor))
                        .focused(focusedButton, equals: button.id)
                    #endif
                }

                if hasBarMenu {
                    Menu {
                        MenuContent(
                            provider: provider,
                            buttons: overflowButtons,
                            menuButtons: menuButtons
                        )
                    } label: {
                        Label(L10n.menu, systemImage: "ellipsis")
                    }
                    .menuStyle(.button)
                    .labelStyle(ItemActionButtonLabelStyle())
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary, .secondary)
                    .focused(focusedButton, equals: ItemView.Component.menu)
                }
            }
            .frame(height: UIDevice.isTV ? 56 : 44)
            .environmentObject(provider)
            .buttonBorderShape(.capsule)
            #if os(tvOS)
            .buttonStyle(.capsule(isSelectionActive: false))
            .controlSize(.large)
            #else
            .buttonStyle(BasicHoverButtonStyle())
            #endif
            .font(.title3)
            .fontWeight(.semibold)
        }
    }
}

extension ItemActionButtons {

    struct Configuration: DynamicProperty {

        @StoredValue(.User.enabledTrailers)
        private var enabledTrailers: TrailerSelection

        @Default(.Customization.itemBarActionButtons)
        private var barActionButtons
        @Default(.Customization.itemMenuActionButtons)
        private var menuActionButtons

        func resolvedButtons(
            for provider: ItemContentGroupProvider
        ) -> (visible: [ItemActionButton], overflow: [ItemActionButton], menu: [ItemActionButton]) {
            ItemActionButtons.resolvedButtons(
                bar: barActionButtons,
                menu: menuActionButtons,
                for: provider,
                enabledTrailers: enabledTrailers
            )
        }
    }

    struct MenuContent: View {

        @ObservedObject
        var provider: ItemContentGroupProvider

        let buttons: [ItemActionButton]
        let menuButtons: [ItemActionButton]

        var body: some View {
            Group {
                ForEach(
                    buttons,
                    content: ItemActionButtons.view(for:)
                )

                if buttons.isNotEmpty, menuButtons.isNotEmpty {
                    Divider()
                }

                ForEach(
                    menuButtons,
                    content: ItemActionButtons.view(for:)
                )
            }
            .environmentObject(provider)
            .withViewContext(.isInMenu)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
        }
    }
}

#if os(tvOS)
/// Focus owns the accent pill; persistent state is communicated by the filled symbol.
private struct TVAccentItemActionButtonStyle: ButtonStyle {

    @Default(.accentColor)
    private var accentColor

    @Environment(\.isFocused)
    private var isFocused
    @Environment(\.isEnabled)
    private var isEnabled
    @Environment(\.isSelected)
    private var isSelected

    func makeBody(configuration: Configuration) -> some View {
        let hasFocus = isEnabled && isFocused

        ZStack {
            Capsule()
                .fill(accentColor.opacity(hasFocus ? (isSelected ? 1 : 0.8) : 0))

            configuration.label
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(hasFocus ? Color.black : accentColor.opacity(0.8))
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .blendMode(hasFocus ? .destinationOut : .normal)
        }
        .fixedSize()
        .compositingGroup()
        .contentShape(.capsule)
        .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
        .animation(.easeOut(duration: 0.12), value: hasFocus)
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
