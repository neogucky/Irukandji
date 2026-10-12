//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import FactoryKit
import SwiftUI

/// `Note`: Used for experimental settings that may be removed or implemented officially. Keep for future settings.
struct ExperimentalSettingsView: View {

    static let isEnabled = true

    @Default(.Experimental.mpvPlayer)
    private var isMPVEnabled
    @Default(.Experimental.serverConnectionAutoSwitch)
    private var isServerConnectionAutoSwitchEnabled
    @Default(.Experimental.videoPlayerEPG)
    private var isVideoPlayerEPGEnabled

    @Injected(\.userSessionManager)
    private var userSessionManager: UserSessionManager

    #if os(tvOS)
    private enum Feature {
        case mpv
        case programmeGuide
    }

    @FocusState
    private var focusedFeature: Feature?
    @State
    private var explainedFeature: Feature = .mpv

    private var featureExplanation: some View {
        VStack(alignment: .leading, spacing: 24) {
            switch explainedFeature {
            case .mpv:
                Text("MPV player")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                Text(
                    "Adds MPV to Settings → Playback → Player. Enabling this option keeps your current player; choose MPV there to use it for videos you start afterwards."
                )
                Text(
                    "MPV is an alternative playback engine that uses Alphane’s cinema controls and Jellyfin watch-progress reporting. If MPV is selected, switching this option off returns the player to VLC."
                )

            case .programmeGuide:
                Text("Live TV programme guide")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                Text(
                    "Adds a Guide panel while watching Live TV. Browse scheduled programmes and choose another channel while staying in the player."
                )
                Text(
                    "Requires Live TV channels and programme data on your Jellyfin server. It applies to live streams started after enabling it; movies and episodes keep their existing controls."
                )
            }
        }
        .font(.system(size: 22))
        .foregroundStyle(AlphaneTheme.secondaryText)
        .lineSpacing(6)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
    #endif

    var body: some View {
        Group {
            #if os(tvOS)
            TVSettingsPage(title: L10n.experimental) {
                HStack(alignment: .top, spacing: 100) {
                    VStack(spacing: 18) {
                        Button {
                            isMPVEnabled.toggle()
                        } label: {
                            TVSettingsRow(title: "MPV engine", value: isMPVEnabled ? TVSettingsText.on : TVSettingsText.off, symbol: nil)
                        }
                        .focused($focusedFeature, equals: .mpv)
                        .accessibilityIdentifier("experimental-mpv")
                        Button {
                            isVideoPlayerEPGEnabled.toggle()
                        } label: {
                            TVSettingsRow(
                                title: "Live TV programme guide",
                                value: isVideoPlayerEPGEnabled ? TVSettingsText.on : TVSettingsText.off,
                                symbol: nil
                            )
                        }
                        .focused($focusedFeature, equals: .programmeGuide)
                        .accessibilityIdentifier("experimental-guide")
                    }
                    .frame(maxWidth: .infinity)
                    .focusSection()
                    featureExplanation
                }
                .defaultFocus($focusedFeature, .mpv, priority: .userInitiated)
                .onChange(of: focusedFeature) { _, feature in
                    if let feature {
                        explainedFeature = feature
                    }
                }
            }
            #else
            Form(systemImage: "flask") {
                // swiftlint:disable hard_coded_display_string
                Toggle("MPV engine", isOn: $isMPVEnabled)

                Toggle("Live TV EPG", isOn: $isVideoPlayerEPGEnabled)

                #if os(iOS)
                Toggle("Auto switch connection", isOn: $isServerConnectionAutoSwitchEnabled)
                #endif

                // swiftlint:enable hard_coded_display_string
            }
            #endif
        }
        .onChange(of: isMPVEnabled) {
            if !isMPVEnabled, Defaults[.VideoPlayer.videoPlayerType] == .mpv {
                Defaults[.VideoPlayer.videoPlayerType] = .vlc
            }
        }
        .onChange(of: isServerConnectionAutoSwitchEnabled) {
            if isServerConnectionAutoSwitchEnabled {
                userSessionManager.scheduleServerConnectionResolution()
            }
        }
        .navigationTitle(L10n.experimental)
    }
}
