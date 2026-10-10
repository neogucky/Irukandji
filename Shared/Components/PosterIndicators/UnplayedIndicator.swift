//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

struct UnplayedIndicator: View {

    @Default(.accentColor)
    private var accentColor

    let count: Int?

    private var badgeColor: Color {
        #if os(tvOS)
        IrukandjiTheme.surface
        #else
        accentColor
        #endif
    }

    private var badgeCorner: QuadrantCorner {
        #if os(tvOS)
        .bottomLeading
        #else
        .topTrailing
        #endif
    }

    var body: some View {
        if let count, count > 0 {
            Quadrant(badgeCorner) {
                QuadrantItem(color: badgeColor) {
                    Text(count.description)
                        .font(.body)
                        .fontWeight(.semibold)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.posterAccessibilityUnplayedCount(count.formatted()))
        } else {
            #if os(tvOS)
            Quadrant(.bottomLeading) {
                QuadrantItem(color: badgeColor) {
                    Text(Image(systemName: "eye.slash"))
                        .fontWeight(.bold)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.unplayed)
            #else
            Q3RightTriangle()
                .fill(accentColor)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel(L10n.unplayed)
            #endif
        }
    }
}

private struct Q3RightTriangle: Shape {

    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        return path
    }
}
