//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

struct TVDiagnosticsSettingsView: View {

    @Router
    private var router

    #if DEBUG
    @Default(.sendProgressReports)
    private var sendProgressReports
    #endif

    var body: some View {
        // swiftlint:disable:next hard_coded_display_string
        TVSettingsPage(title: "Diagnostics") {
            HStack(alignment: .top, spacing: 100) {
                VStack(alignment: .leading, spacing: 24) {
                    Button {
                        router.route(to: .log)
                    } label: {
                        TVSettingsRow(title: L10n.logs)
                    }
                    .accessibilityIdentifier("settings-logs")

                    #if DEBUG
                    Button {
                        sendProgressReports.toggle()
                    } label: {
                        TVSettingsRow(
                            title: L10n.sendProgressReports,
                            value: sendProgressReports ? TVSettingsText.on : TVSettingsText.off,
                            symbol: nil
                        )
                    }
                    Text("Development build")
                        .font(.system(size: 18))
                        .foregroundStyle(AlphaneTheme.secondaryText)
                        .padding(.horizontal, 22)
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 26) {
                    Text("Device details")
                        .font(.system(size: 24, weight: .medium))
                        .accessibilityAddTraits(.isHeader)
                    LabeledContent("SoC & GPU", value: PlaybackCapabilities.gpuName)
                    LabeledContent("HDR playback", value: PlaybackCapabilities.isDeviceHDRCapable ? L10n.yes : L10n.no)
                    LabeledContent(VideoCodec.av1.displayTitle, value: PlaybackCapabilities.supportsAV1 ? L10n.yes : L10n.no)
                    LabeledContent(VideoCodec.hevc.displayTitle, value: PlaybackCapabilities.supportsHEVC ? L10n.yes : L10n.no)
                    LabeledContent(VideoCodec.vp9.displayTitle, value: PlaybackCapabilities.supportsVP9 ? L10n.yes : L10n.no)
                }
                .font(.system(size: 22))
                .foregroundStyle(AlphaneTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
