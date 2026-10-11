//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation
import JellyfinAPI

@MainActor
final class HomeDiscoveryViewModel: ViewModel, WithRefresh {
    typealias Loader = @MainActor (HomeDiscoveryRow) async throws -> [BaseItemDto]
    typealias HistoryLoader = @MainActor () async throws -> [BaseItemDto]
    typealias RefreshLoader = @MainActor (HomeDiscoveryRow, [BaseItemDto]) async throws -> [BaseItemDto]
    typealias ItemOrder = ([BaseItemDto]) -> [BaseItemDto]
    typealias Background = HomeDiscoveryViewModel

    struct LoadedRow: Identifiable {
        let definition: HomeDiscoveryRow
        let group: PosterGroup<StaticLibrary<BaseItemDto>>
        var id: String {
            definition.id
        }

        @MainActor
        init(definition: HomeDiscoveryRow, items: [BaseItemDto]) {
            self.definition = definition
            self.group = PosterGroup(
                id: definition.id,
                library: StaticLibrary(title: definition.title, id: definition.id, elements: items),
                posterDisplayType: .landscape,
                environment: .init(isHeaderButtonEnabled: false, minimumItemCount: HomeDiscoveryRow.minimumItemCount)
            )
            group.viewModel.elements.append(contentsOf: items)
        }
    }

    @Published
    private(set) var rows: [LoadedRow] = []
    @Published
    private(set) var isLoading = false
    @Published
    private(set) var hasMore = true
    @Published
    private(set) var hasLoadError = false
    @Published
    private(set) var refreshRevision = 0

    private let loader: Loader
    private let historyLoader: HistoryLoader
    private let refreshLoader: RefreshLoader
    private let itemOrder: ItemOrder
    private var candidates: [HomeDiscoveryRow]
    private var cursor = 0
    private var needsHistory = true
    private var staleRowIDs = Set<String>()
    private var refreshingRowIDs = Set<String>()
    private var loadTask: Task<Void, Never>?

    var background: HomeDiscoveryViewModel {
        get { self }
        set {}
    }

    init(
        catalog: [HomeDiscoveryRow] = HomeDiscoveryRow.catalog,
        shuffle: Bool = true,
        loader: @escaping Loader,
        historyLoader: @escaping HistoryLoader = { [] },
        refreshLoader: RefreshLoader? = nil,
        itemOrder: @escaping ItemOrder = { $0.shuffled() }
    ) {
        self.candidates = shuffle ? catalog.shuffled() : catalog
        self.itemOrder = itemOrder
        self.loader = loader
        self.historyLoader = historyLoader
        self.refreshLoader = refreshLoader ?? { row, _ in try await loader(row) }
        self.hasMore = !catalog.isEmpty
        super.init()
    }

    func refresh() {
        markStale()
    }

    private func markStale() {
        // Refresh only rows that appear, preserving order and focus on return
        // from details. Unvisited recipes still perform no network requests.
        staleRowIDs.formUnion(rows.map(\.id))
        needsHistory = true
        hasMore = true
        refreshRevision += 1
    }

    func refresh() async {
        markStale()
    }

    func shouldPrefetch(after id: String) -> Bool {
        rows.suffix(2).contains { $0.id == id }
    }

    /// One in-flight batch even when several visible rows request prefetch.
    func loadMore() async {
        if let loadTask {
            await loadTask.value
            return
        }
        guard hasMore || needsHistory else { return }

        isLoading = true
        hasLoadError = false
        let task = Task { await self.loadBatch() }
        loadTask = task
        await task.value
        loadTask = nil
        isLoading = false
    }

    private func addHistoryCandidates() async {
        guard needsHistory else { return }

        needsHistory = false
        guard let history = try? await historyLoader() else { return }

        let existingIDs = Set(candidates.map(\.id)).union(rows.map(\.id))
        for row in HomeDiscoveryRow.similarRows(recentlyPlayed: history) where !existingIDs.contains(row.id) {
            // Insert only among unseen recipes; loaded rows never move.
            candidates.insert(row, at: Int.random(in: cursor ... candidates.count))
        }
        hasMore = cursor < candidates.count
    }

    private func loadBatch() async {
        await addHistoryCandidates()
        while cursor < candidates.count {
            let batch = Array(candidates[cursor ..< min(cursor + 3, candidates.count)])
            let results = await withTaskGroup(of: (Int, [BaseItemDto]?).self) { group in
                for (index, definition) in batch.enumerated() {
                    group.addTask { [loader] in
                        await (index, try? loader(definition))
                    }
                }
                var results: [(Int, [BaseItemDto]?)] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }
            // A disconnected server leaves the cursor in place for an explicit
            // retry rather than silently exhausting every recipe.
            guard results.contains(where: { $0.1 != nil }) else {
                hasLoadError = true
                return
            }

            cursor += batch.count
            let validRows = results.compactMap { index, items -> LoadedRow? in
                guard let items else { return nil }

                let definition = batch[index]
                // Shuffle once per row, after eligibility filtering. Refreshing
                // metadata on Back keeps this order and the focused card stable.
                let normalized = Array(itemOrder(definition.normalized(items)).prefix(HomeDiscoveryRow.itemLimit))
                guard normalized.count >= HomeDiscoveryRow.minimumItemCount else { return nil }

                return LoadedRow(definition: definition, items: normalized)
            }
            rows += validRows
            hasMore = cursor < candidates.count
            if !validRows.isEmpty {
                return
            }
            // Empty/sparse rows consume no vertical space; continue looking for
            // a usable batch without exposing their headings or placeholders.
        }
        hasMore = false
    }

    func refreshRow(_ id: String) async {
        guard staleRowIDs.contains(id),
              !refreshingRowIDs.contains(id),
              let row = rows.first(where: { $0.id == id })
        else { return }

        refreshingRowIDs.insert(id)
        defer { refreshingRowIDs.remove(id) }
        do {
            let previousItems = row.group.viewModel.elements.elements
            let items = try await row.definition.normalized(refreshLoader(row.definition, previousItems))
            guard !Task.isCancelled else { return }

            let updatedByID = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.id.map { ($0, item) } })
            let ordered = previousItems.compactMap { item in item.id.flatMap { updatedByID[$0] } }
            row.group.viewModel.elements = .init(ordered, uniquingIDsWith: { existing, _ in existing })
            staleRowIDs.remove(id)
        } catch {
            // Keep cached cards during a temporary outage. The next appearance
            // or refresh can retry; a failed request never empties a good row.
        }
    }
}
