//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import SwiftUI

@MainActor
final class TabCoordinator: ObservableObject {

    struct SelectedEvent {
        let isRoot: Bool
        let isRepeat: Bool
    }

    typealias TabData = (
        item: TabItem,
        coordinator: NavigationCoordinator,
        publisher: TabItemSelectedPublisher
    )

    @Published
    var selectedTabID: String! = nil {
        didSet {
            guard let tab = tabs.first(property: \.item.id, equalTo: selectedTabID) else { return }

            tab.publisher.send(
                .init(
                    isRoot: tab.coordinator.path.isEmpty,
                    isRepeat: oldValue == selectedTabID
                )
            )
        }
    }

    let tabs: [TabData]

    private var cancellables: Set<AnyCancellable> = []

    init(@ArrayBuilder<TabItem> tabs: () -> [TabItem]) {
        let tabs = tabs()
        self.tabs = tabs.map { tab in
            (tab, NavigationCoordinator(usesNavigationStack: UIDevice.isTV), TabItemSelectedPublisher())
        }
        self.selectedTabID = tabs.first?.id

        // The shared header must react to pushes/pops as well as tab changes.
        for tab in self.tabs {
            tab.coordinator
                .objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func route(to route: NavigationRoute) async {
        guard let tab = tabs.first(where: { $0.item.id == selectedTabID }) else { return }

        tab.coordinator.push(route)
    }
}
