//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

extension SelectUserView {

    struct EmptyUserView: View {

        #if os(tvOS)
        @FocusState
        private var isFocused: Bool
        #endif

        let action: () -> Void

        private let columns: CGFloat = UIDevice.isPhone ? 2 : 5

        @ViewBuilder
        private var imageView: some View {
            RelativeSystemImageView(systemName: "plus")
                .foregroundStyle(Color.secondary)
                .aspectRatio(1, contentMode: .fit)
                .backport
                .glassEffect(in: .circle)
        }

        @ViewBuilder
        private var addUserButton: some View {
            Button(action: action) {
                #if os(tvOS)
                VStack {
                    imageView
                        .tvFocusBorder(isFocused: isFocused, shape: Circle())

                    Text(L10n.addUser)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                #else
                VStack {
                    imageView

                    Text(L10n.addUser)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
                #endif
            }
            .foregroundStyle(.primary, .secondary)
            .buttonBorderShape(.circle)
            #if os(tvOS)
                .buttonStyle(ArtworkButtonStyle())
                .focused($isFocused)
            #endif
        }

        var body: some View {
            GeometryReader { geometry in
                addUserButton
                    .frame(maxWidth: (geometry.size.width - EdgeInsets.edgePadding * (columns + 1)) / columns)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .focusSection()
            }
        }
    }
}
