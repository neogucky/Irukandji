//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct SearchView: View {

    @FocusState
    private var isSearchFocused: Bool

    @State
    private var searchQuery = ""

    @StateObject
    private var focusCoordinator: FocusCoordinator = .init()
    @StateObject
    private var viewModel = SearchViewModel()

    @TabItemSelected
    private var tabItemSelected

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                RetryableContentView(
                    error: viewModel.canSearch && viewModel.state == .error ? viewModel.error : nil,
                    retry: { await viewModel.retrySearch() }
                ) {
                    switch viewModel.state {
                    case .error:
                        EmptyView()

                    case .initial:
                        if viewModel.canSearch {
                            if viewModel.isEmpty {
                                Text(L10n.noResults)
                                    .font(.system(size: 22, weight: .medium))
                                #if os(tvOS)
                                    .foregroundStyle(AlphaneTheme.secondaryText)
                                #else
                                    .foregroundStyle(.secondary)
                                #endif
                                    .padding(.top, 36)
                            } else {
                                ContentGroupVStack(
                                    groups: viewModel.itemContentGroupViewModel.groups
                                )
                            }
                        }

                    case .searching:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .focusSection()
            }
        }
        .ignoresSafeArea(edges: .horizontal)
        .mainNavigationScrollObserver()
        .scrollIndicators(.hidden)
        .animation(.linear(duration: 0.2), value: viewModel.state)
        .ignoresSafeArea(.keyboard)
        .navigationTitle(L10n.search)
        .toolbarTitleDisplayMode(.inline)
        .searchFocused($isSearchFocused)
        .onReceive(tabItemSelected) { event in
            if event.isRepeat, event.isRoot {
                isSearchFocused = true
            }
        }
        .onChange(of: searchQuery) {
            viewModel.search(query: searchQuery)
        }
        .searchable(
            text: $searchQuery,
            prompt: L10n.search
        )
        .environmentObject(focusCoordinator)
        #if os(tvOS)
            .modifier(SearchSafeAreaModifier())
        #endif
    }
}
