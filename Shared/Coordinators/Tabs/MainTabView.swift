//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import FactoryKit
import JellyfinAPI
import SwiftUI

struct MainTabView: View {

    #if os(tvOS)
    @FocusState
    private var focusedTabID: String?

    @State
    private var loadedTabIDs: Set<String> = []
    #endif

    @InjectedObject(\.userSessionManager)
    private var userSessionManager

    @StateObject
    private var tabCoordinator: TabCoordinator

    init() {
        _tabCoordinator = StateObject(wrappedValue: Self.defaultTabCoordinator)
    }

    private static var defaultTabCoordinator: TabCoordinator {
        #if os(iOS)
        TabCoordinator {
            TabItem.contentGroup(provider: DefaultContentGroupProvider())
            TabItem.search
            TabItem.media
        }
        #else
        TabCoordinator {
            TabItem.contentGroup(provider: DefaultContentGroupProvider())
            TabItem.library(
                title: L10n.tvShowsCapitalized,
                systemName: "tv",
                filters: .init(itemTypes: [.series])
            )
            TabItem.library(
                title: L10n.movies,
                systemName: "film",
                filters: .init(itemTypes: [.movie])
            )
            TabItem.search
            TabItem.media
            TabItem.settings
        }
        #endif
    }

    private func routePendingDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }

        Task { @MainActor in
            let route = deepLink.route()
            await tabCoordinator.route(to: route)
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: TabCoordinator.TabData) -> some View {
        NavigationInjectionView(coordinator: tab.coordinator) {
            tab.item.content
            #if os(iOS)
                .if(tabCoordinator.tabs.first?.item.id == tab.item.id) { view in
                    view.topBarTrailing {
                        FirstTabSettingsBarButton()
                    }
                }
            #endif
        }
        .environmentObject(tabCoordinator)
        .environment(\.tabItemSelected, tab.publisher)
    }

    #if os(tvOS)
    private func selectTab(_ item: TabItem) {
        if let tab = tabCoordinator.tabs.first(where: { $0.item.id == item.id }) {
            tab.coordinator.path.removeAll()
        }
        tabCoordinator.selectedTabID = item.id
    }

    private var navigationHeader: some View {
        SelectionTrack(
            tabCoordinator.tabs.map(\.item),
            selection: focusedTabID ?? tabCoordinator.selectedTabID,
            focus: $focusedTabID,
            action: selectTab
        )
        .controlSize(.extraLarge)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .edgePadding(.horizontal)
        .background(IrukandjiTheme.background)
        .focusSection()
        .defaultFocus($focusedTabID, tabCoordinator.selectedTabID, priority: .userInitiated)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tabBar)
    }

    private var tvOSTabContent: some View {
        VStack(spacing: 0) {
            navigationHeader

            GeometryReader { proxy in
                ZStack {
                    ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                        let isActive = tab.item.id == tabCoordinator.selectedTabID
                        if isActive || loadedTabIDs.contains(tab.item.id) {
                            tabRoot(tab)
                                .environment(\.tabSafeAreaInsets, proxy.safeAreaInsets)
                                .environment(\.isMainNavigationFocused, focusedTabID != nil)
                                .opacity(isActive ? 1 : 0)
                                .disabled(!isActive)
                                .allowsHitTesting(isActive)
                                .accessibilityHidden(!isActive)
                                .zIndex(isActive ? 1 : 0)
                                .onChange(of: tab.coordinator.path.count) { oldCount, newCount in
                                    guard isActive, newCount > oldCount else { return }

                                    // Keep focus on the current category while its new page loads.
                                    focusedTabID = tab.item.id
                                }
                        }
                    }
                }
            }
            .clipped()
        }
        .ignoresSafeArea(.container)
        .onAppear {
            loadedTabIDs.insert(tabCoordinator.selectedTabID)
            focusedTabID = tabCoordinator.selectedTabID
        }
        .onChange(of: focusedTabID) { _, tabID in
            guard let tabID, tabID != tabCoordinator.selectedTabID else { return }

            // Switch immediately without replacing the focused header button.
            tabCoordinator.selectedTabID = tabID
        }
        .onChange(of: tabCoordinator.selectedTabID) { _, tabID in
            guard let tabID else { return }

            loadedTabIDs.insert(tabID)
        }
        .onExitCommand {
            guard let tab = tabCoordinator.tabs.first(where: { $0.item.id == tabCoordinator.selectedTabID }) else { return }

            if tab.coordinator.path.isEmpty {
                focusedTabID = tab.item.id
            } else {
                tab.coordinator.path.removeLast()
            }
        }
    }
    #else
    private var iOSTabContent: some View {
        TabView(selection: $tabCoordinator.selectedTabID) {
            ForEach(tabCoordinator.tabs, id: \.item.id) { tab in
                Tab(
                    value: tab.item.id,
                    role: tab.item.id == TabItem.search.id ? .search : nil
                ) {
                    tabRoot(tab)
                } label: {
                    Label(
                        tab.item.displayTitle,
                        systemImage: tab.item.systemImage
                    )
                    .symbolRenderingMode(.monochrome)
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private func tabContent() -> some View {
        #if os(tvOS)
        tvOSTabContent
        #else
        iOSTabContent
        #endif
    }

    var body: some View {
        tabContent()
            .onChange(of: userSessionManager.pendingDeepLink) {
                routePendingDeepLink(userSessionManager.consumePendingDeepLink())
            }
            .onReceive(userSessionManager.routePublisher) { route in
                Task { @MainActor in
                    await tabCoordinator.route(to: route)
                }
            }
        #if os(tvOS)
            .background(alignment: .top) {
                FocusedPosterCinematicBackgroundView()
            }
        #endif
    }
}

#if os(iOS)
private struct FirstTabSettingsBarButton: View {

    @Injected(\.currentUserSession)
    private var userSession

    @Router
    private var router

    var body: some View {
        if router.isRootOfPath,
           let userSession
        {
            SettingsBarButton(
                server: userSession.server,
                user: userSession.user
            ) {
                router.route(to: .settings)
            }
        }
    }
}
#endif
