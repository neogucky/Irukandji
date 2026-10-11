//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

struct HomeDiscoveryContentGroup: ContentGroup {
    let id = "home-discovery"
    let viewModel: HomeDiscoveryViewModel

    init(userSession: UserSession, libraries: [BaseItemDto]) {
        viewModel = HomeDiscoveryViewModel { row in
            try await HomeRowLibrary(row: row, libraries: libraries).retrievePage(
                environment: .default,
                pageState: .init(pageOffset: 0, pageSize: HomeDiscoveryRow.itemLimit, userSession: userSession)
            )
        } historyLoader: {
            var parameters = Paths.GetItemsParameters()
            parameters.userID = userSession.user.id
            parameters.includeItemTypes = [.movie, .episode]
            parameters.isRecursive = true
            parameters.isPlayed = true
            parameters.isMissing = false
            parameters.isUnaired = false
            parameters.enableUserData = true
            parameters.enableTotalRecordCount = false
            parameters.sortBy = [.datePlayed]
            parameters.sortOrder = [.descending]
            parameters.limit = 16
            let response = try await userSession.client.send(Paths.getItems(parameters: parameters))
            return response.value.items ?? []
        } refreshLoader: { row, items in
            let ids = items.compactMap(\.id)
            guard !ids.isEmpty else { return [] }

            var parameters = Paths.GetItemsParameters()
            parameters.userID = userSession.user.id
            parameters.ids = ids
            parameters.enableUserData = true
            parameters.fields = PosterSubtitleField.itemFields
            let response = try await userSession.client.send(Paths.getItems(parameters: parameters))
            return row.normalized(response.value.items ?? [])
        }
    }

    func body(with viewModel: HomeDiscoveryViewModel) -> some View {
        DiscoveryView(viewModel: viewModel)
    }

    private struct DiscoveryView: View {
        @ObservedObject
        var viewModel: HomeDiscoveryViewModel

        @State
        private var visibleRows = Set<String>()

        private func prefetchIfNeeded() {
            guard !viewModel.hasLoadError,
                  visibleRows.contains(where: { viewModel.shouldPrefetch(after: $0) })
            else { return }

            Task { await viewModel.loadMore() }
        }

        var body: some View {
            LazyVStack(alignment: .leading, spacing: 60) {
                ForEach(viewModel.rows) { row in
                    RowView(row: row)
                        .id(row.id)
                        .coordinatedFocus(row.id)
                        .task(id: viewModel.refreshRevision) {
                            await viewModel.refreshRow(row.id)
                        }
                        .onScrollVisibilityChange(threshold: 0.01) { visible in
                            if visible {
                                visibleRows.insert(row.id)
                            } else {
                                visibleRows.remove(row.id)
                            }
                            prefetchIfNeeded()
                        }
                }
                if viewModel.hasLoadError {
                    HStack(spacing: 20) {
                        Text("Couldn't load more suggestions")
                            .foregroundStyle(AlphaneTheme.secondaryText)
                        Button(L10n.retry) {
                            Task { await viewModel.loadMore() }
                        }
                        .buttonStyle(.capsule)
                        .controlSize(.regular)
                        .coordinatedFocus("home-discovery-retry")
                    }
                    .edgePadding(.horizontal)
                    .frame(height: 100)
                } else if viewModel.hasMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .task { await viewModel.loadMore() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: viewModel.isLoading) { _, loading in
                if !loading {
                    prefetchIfNeeded()
                }
            }
        }
    }

    private struct RowView: View {
        let row: HomeDiscoveryViewModel.LoadedRow
        @ObservedObject
        private var viewModel: PagingLibraryViewModel<StaticLibrary<BaseItemDto>>

        init(row: HomeDiscoveryViewModel.LoadedRow) {
            self.row = row
            self.viewModel = row.group.viewModel
        }

        var body: some View {
            if viewModel.elements.count >= HomeDiscoveryRow.minimumItemCount {
                row.group
                    .body(with: viewModel)
                    .frame(minHeight: 300, alignment: .topLeading)
            }
        }
    }
}
