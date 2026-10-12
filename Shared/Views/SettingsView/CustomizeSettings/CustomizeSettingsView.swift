//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct CustomizeSettingsView: View {

    #if os(tvOS)
    @FocusState
    private var focusedControl: String?
    #endif

    @Default(.Customization.Search.enabledDrawerFilters)
    private var searchEnabledDrawerFilters

    @Router
    private var router

    var body: some View {
        #if os(tvOS)
        TVSettingsPage(title: L10n.appearance) {
            TVSettingsAppearanceColumn(showsTitle: false, focus: $focusedControl)
                .frame(maxWidth: 600)
                .frame(height: 320)
        }
        #else
        Form(systemImage: "gear") {

            Section {
                ChevronButton(L10n.search) {
                    router.route(to: .itemFilterDrawerSelector(selection: $searchEnabledDrawerFilters))
                }

            } header: {
                Text(L10n.filters)
            }

            ChevronButton(L10n.items) {
                router.route(to: .itemSettings)
            }

            ChevronButton(L10n.libraries) {
                router.route(to: .librarySettings)
            }

            ChevronButton(L10n.posters) {
                router.route(to: .posterSettings)
            }

            ChevronButton(L10n.videoPlayer) {
                router.route(to: .videoPlayerSettings)
            }

            HomeSection()
        }
        .navigationTitle(L10n.advanced)
        #endif
    }
}
