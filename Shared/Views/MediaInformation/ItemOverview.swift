//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct ItemOverviewView: View {

    @Router
    private var router

    @SharedBaseItem
    var item: BaseItemDto

    #if os(tvOS)
    @StateObject
    private var overviewScrollController = OverviewScrollController()
    #endif

    var body: some View {
        Group {
            #if os(tvOS)
            TVOverviewText(item: item, controller: overviewScrollController)
                .edgePadding()
                .focusable()
                .focusEffectDisabled()
                .onMoveCommand(perform: overviewScrollController.move)
            #else
            overviewScrollView
            #endif
        }
        .navigationTitle(item.displayTitle)
        .toolbarTitleDisplayMode(.inline)
        .navigationBarCloseButton {
            router.dismiss()
        }
    }

    private var overviewScrollView: some View {
        ScrollView {
            VStack(alignment: UIDevice.isTV ? .center : .leading, spacing: 10) {
                if let firstTagline = item.taglines?.first {
                    Text(firstTagline)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                }

                if let itemOverview = item.overview {
                    Text(itemOverview)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .edgePadding()
        }
        .scrollIndicators(.hidden)
    }
}

#if os(tvOS)
/// A native text view keeps long, even single-paragraph synopses scrollable with
/// the Siri Remote. A focusable SwiftUI ScrollView alone does not scroll text.
private struct TVOverviewText: UIViewRepresentable {

    let item: BaseItemDto
    let controller: OverviewScrollController

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        controller.view = view
        view.backgroundColor = .clear
        view.isSelectable = false
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let text = NSMutableAttributedString()
        if let tagline = item.taglines?.first, !tagline.isEmpty {
            text.append(NSAttributedString(string: tagline + "\n\n", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title3),
                .foregroundColor: UIColor.white,
            ]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        text.append(NSAttributedString(string: item.overview ?? "", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]))
        // Avoid resetting the scroll position during unrelated view updates.
        if view.attributedText != text {
            view.attributedText = text
        }
    }
}

private final class OverviewScrollController: ObservableObject {

    weak var view: UITextView?

    func move(_ direction: MoveCommandDirection) {
        guard let view, direction == .up || direction == .down else { return }
        let minimum = -view.adjustedContentInset.top
        let maximum = max(minimum, view.contentSize.height - view.bounds.height + view.adjustedContentInset.bottom)
        let distance = view.bounds.height * 0.65 * (direction == .down ? 1 : -1)
        let offset = min(maximum, max(minimum, view.contentOffset.y + distance))
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: offset), animated: true)
    }
}
#endif
