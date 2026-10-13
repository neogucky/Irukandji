//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import JellyfinAPI
import SwiftUI

struct TVSettingsView: View {

    @Default(.VideoPlayer.videoPlayerType)
    private var player
    @Default(.VideoPlayer.Playback.appMaximumResolution)
    private var maximumResolution
    @Default(.VideoPlayer.Playback.appMaximumBitrate)
    private var maximumBitrate

    @InjectedObject(\.userSessionManager)
    private var userSessionManager
    @Environment(\.navigationFocusStore)
    private var focusStore
    @Environment(\.navigationFocusPageID)
    private var pageID
    @Router
    private var router

    @FocusState
    private var focusedControl: String?
    @State
    private var isSigningOut = false
    @StateObject
    private var userViewModel: ServerUserAdminViewModel

    private static let focusScope = "settings"

    init() {
        _userViewModel = StateObject(wrappedValue: ServerUserAdminViewModel(
            user: Container.shared.currentUserSession()?.user.data ?? UserDto()
        ))
    }

    private var qualitySummary: String {
        if maximumResolution == .max {
            return maximumBitrate.displayTitle
        }
        return maximumResolution.displayTitle
    }

    private func open(_ route: NavigationRoute, from control: String) {
        focusStore?.remember(.init(scope: Self.focusScope, item: control), on: pageID)
        router.route(to: route)
    }

    private func restoreFocus(_ request: NavigationFocusStore.Request?) {
        guard request?.pageID == pageID, request?.target.scope == Self.focusScope,
              let control = request?.target.item.base as? String else { return }

        focusedControl = control
    }

    private func signOut() {
        guard !isSigningOut else { return }

        isSigningOut = true
        Task { @MainActor in
            UIDevice.impact(.medium)
            await userSessionManager.signOut(reason: .explicit)
            router.dismiss()
        }
    }

    private func setAutoPlay(_ enabled: Bool) {
        guard var configuration = userViewModel.user.configuration else { return }

        configuration.enableNextEpisodeAutoPlay = enabled
        userViewModel.updateConfiguration(configuration)
    }

    private var profileActions: some View {
        HStack(spacing: 40) {
            if let session = userSessionManager.currentSession {
                HStack(spacing: 18) {
                    UserProfileImage(
                        userID: session.user.id,
                        source: session.user.profileImageSource(client: session.client)
                    )
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.user.username)
                            .font(.system(size: 22, weight: .medium))
                        Text(session.server.name)
                            .font(.system(size: 18))
                    }
                    .lineLimit(1)
                }
                .foregroundStyle(AlphaneTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 22)

                HStack(spacing: 24) {
                    Button {
                        open(.localUserSecurity, from: "pin")
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: "lock")
                            // swiftlint:disable:next hard_coded_display_string
                            Text("Profile PIN")
                            Text(session.user.accessPolicy == .requirePin ? TVSettingsText.on : TVSettingsText.off)
                                .font(.system(size: 20))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16))
                        }
                        .lineLimit(1)
                    }
                    .focused($focusedControl, equals: "pin")
                    .accessibilityIdentifier("settings-pin")

                    Button(action: signOut) {
                        // swiftlint:disable:next hard_coded_display_string
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .focused($focusedControl, equals: "logout")
                    .disabled(isSigningOut)
                    .accessibilityIdentifier("settings-logout")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(AlphaneTheme.surface, in: RoundedRectangle(cornerRadius: 24))
        .focusSection()
        .defaultFocus($focusedControl, "logout", priority: .userInitiated)
    }

    private var playbackColumn: some View {
        TVSettingsColumn(title: L10n.playback) {
            Menu {
                Picker(L10n.player, selection: $player) {
                    ForEach(VideoPlayerType.supportedCases, id: \.self) { player in
                        Text(player.displayTitle).tag(player)
                    }
                }
            } label: {
                TVSettingsRow(title: L10n.player, value: player.displayTitle, symbol: "chevron.down")
            }
            .focused($focusedControl, equals: "player")
            .accessibilityIdentifier("settings-player")

            Menu {
                Picker(L10n.resolution, selection: $maximumResolution)
                Picker(L10n.bitrate, selection: $maximumBitrate) {
                    ForEach(PlaybackBitrate.videoBitrates, id: \.self) { bitrate in
                        Text(bitrate.displayTitle).tag(bitrate)
                    }
                }
                Button(L10n.playbackQuality) {
                    open(.playbackQualitySettings, from: "quality")
                }
            } label: {
                // swiftlint:disable:next hard_coded_display_string
                TVSettingsRow(title: "Video quality", value: qualitySummary, symbol: "chevron.down")
            }
            .focused($focusedControl, equals: "quality")
            .accessibilityIdentifier("settings-quality")

            Button {
                setAutoPlay(userViewModel.user.configuration?.enableNextEpisodeAutoPlay != true)
            } label: {
                // swiftlint:disable:next hard_coded_display_string
                TVSettingsRow(
                    title: "Auto-play next episode",
                    value: userViewModel.user.configuration?.enableNextEpisodeAutoPlay == true ? TVSettingsText.on : TVSettingsText.off,
                    symbol: nil
                )
            }
            .focused($focusedControl, equals: "autoplay")
            .disabled(userViewModel.user.configuration == nil || userViewModel.background.is(.updating))
            .accessibilityIdentifier("settings-autoplay")

            Button {
                open(.tvAudioSubtitleSettings, from: "tracks")
            } label: {
                // swiftlint:disable:next hard_coded_display_string
                TVSettingsRow(title: "Audio & subtitles")
            }
            .focused($focusedControl, equals: "tracks")
            .accessibilityIdentifier("settings-tracks")

            Button {
                open(.tvPlaybackPreferences, from: "playback-preferences")
            } label: {
                // swiftlint:disable:next hard_coded_display_string
                TVSettingsRow(title: "Playback preferences")
            }
            .focused($focusedControl, equals: "playback-preferences")
        }
    }

    private var toolsColumn: some View {
        // swiftlint:disable:next hard_coded_display_string
        TVSettingsColumn(title: "Tools") {
            if ExperimentalSettingsView.isEnabled {
                Button {
                    open(.experimentalSettings, from: "experimental")
                } label: {
                    TVSettingsRow(title: L10n.experimental)
                }
                .focused($focusedControl, equals: "experimental")
                .accessibilityIdentifier("settings-experimental")
            }
            Button {
                open(.tvDiagnostics, from: "diagnostics")
            } label: {
                // swiftlint:disable:next hard_coded_display_string
                TVSettingsRow(title: "Diagnostics")
            }
            .focused($focusedControl, equals: "diagnostics")
            .accessibilityIdentifier("settings-diagnostics")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileActions
                .padding(.bottom, 42)

            HStack(alignment: .top, spacing: 32) {
                playbackColumn
                columnDivider
                TVSettingsAppearanceColumn(focus: $focusedControl)
                columnDivider
                toolsColumn
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .buttonStyle(TVSettingsButtonStyle())
        .menuStyle(TVSettingsMenuStyle())
        .defaultFocus($focusedControl, "logout", priority: .userInitiated)
        .background(AlphaneTheme.background.ignoresSafeArea())
        .onAppear {
            restoreFocus(focusStore?.request)
            // PIN changes update the stored profile independently of the server DTO.
            userViewModel.refresh()
        }
        .onChange(of: focusedControl) { _, control in
            guard let control else { return }

            focusStore?.didRestore(.init(scope: Self.focusScope, item: control), on: pageID)
        }
        .onReceive(focusStore?.$request.eraseToAnyPublisher() ?? Combine.Empty<NavigationFocusStore.Request?, Never>()
            .eraseToAnyPublisher())
        {
            restoreFocus($0)
        }
        .errorMessage($userViewModel.error)
    }

    private var columnDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1)
            .accessibilityHidden(true)
    }
}

/// Only preferences used by Alphane's tvOS artwork and focus design are exposed.
struct TVSettingsAppearanceColumn: View {

    var showsTitle = true
    let focus: FocusState<String?>.Binding

    @Default(.userAccentColor)
    private var accentColor
    @Default(.Customization.Poster.configuration)
    private var posterConfiguration

    var body: some View {
        TVSettingsColumn(title: L10n.appearance, showsTitle: showsTitle) {
            ColorPicker(L10n.accentColor, selection: $accentColor, supportsOpacity: false)
                .focused(focus, equals: "accent")
                .accessibilityIdentifier("settings-accent")
            indicatorButton("Watched badges", indicator: .played)
                .focused(focus, equals: "watched")
                .accessibilityIdentifier("settings-watched")
            indicatorButton("Progress indicators", indicator: .progress)
                .focused(focus, equals: "progress")
                .accessibilityIdentifier("settings-progress")
        }
    }

    private func indicatorButton(_ title: String, indicator: PosterIndicator) -> some View {
        let isOn = posterConfiguration.indicators.contains(indicator)
        return Button {
            if isOn {
                posterConfiguration.indicators.remove(indicator)
            } else {
                posterConfiguration.indicators.insert(indicator)
            }
        } label: {
            TVSettingsRow(title: title, value: isOn ? TVSettingsText.on : TVSettingsText.off, symbol: nil)
        }
        .accessibilityValue(isOn ? TVSettingsText.on : TVSettingsText.off)
    }
}
