//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct PillGroup<Element: Displayable>: ContentGroup {

    enum Presentation {
        case section
        case inline
    }

    private let action: (Router.Wrapper, Element) -> Void
    private let displayTitle: String
    private let elements: [Element]
    private let presentation: Presentation
    let id: String

    var _shouldBeResolved: Bool {
        elements.isNotEmpty
    }

    init(
        displayTitle: String,
        id: String,
        elements: [Element],
        presentation: Presentation = .section,
        action: @escaping (Router.Wrapper, Element) -> Void
    ) {
        self.action = action
        self.displayTitle = displayTitle
        self.id = id
        self.elements = elements
        self.presentation = presentation
    }

    func body(with viewModel: Empty) -> Body {
        Body(
            action: action,
            displayTitle: displayTitle,
            elements: elements,
            presentation: presentation
        )
    }

    struct Body: View {

        @Router
        private var router

        let action: (Router.Wrapper, Element) -> Void
        let displayTitle: String
        let elements: [Element]
        let presentation: Presentation

        var body: some View {
            ContentGroupSection {
                ScrollView(.horizontal) {
                    HStack(spacing: EdgeInsets.itemSpacing) {
                        ForEach(elements) { element in
                            Button {
                                action(router, element)
                            } label: {
                                if let imageable = element as? SystemImageable {
                                    Label(element.displayTitle, systemImage: imageable.systemImage)
                                } else {
                                    Text(element.displayTitle)
                                }
                            }
                            .foregroundStyle(.primary, .secondary)
                        }
                    }
                    .labelStyle(.leadingIcon)
                    .buttonStyle(.capsule)
                    .controlSize(UIDevice.isTV && presentation == .section ? .large : .regular)
                    .edgePadding(.horizontal)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            } header: {
                if presentation == .section, displayTitle.isNotEmpty {
                    Text(displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .accessibility(addTraits: [.isHeader])
                        .edgePadding(.horizontal)
                }
            }
            .focusSection()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(displayTitle)
        }
    }
}
