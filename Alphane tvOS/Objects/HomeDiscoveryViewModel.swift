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
    typealias RetryDelay = (Int) -> Duration
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
    private(set) var isWaitingToLoad = false
    @Published
    private(set) var refreshRevision = 0

    private let loader: Loader
    private let historyLoader: HistoryLoader
    private let refreshLoader: RefreshLoader
    private let itemOrder: ItemOrder
    private let retryDelay: RetryDelay
    private var candidates: [HomeDiscoveryRow]
    private var cursor = 0
    private var needsHistory = true
    private var staleRowIDs = Set<String>()
    private var refreshingRowIDs = Set<String>()
    private var loadTask: Task<Bool, Never>?
    private var retryTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private var consecutiveFailures = 0
    private var isActive = true
    private var loadRequested = false

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
        itemOrder: @escaping ItemOrder = { $0.shuffled() },
        retryDelay: @escaping RetryDelay = { .seconds([3, 6, 12, 24, 30][min($0 - 1, 4)]) }
    ) {
        self.candidates = shuffle ? catalog.shuffled() : catalog
        self.itemOrder = itemOrder
        self.retryDelay = retryDelay
        self.loader = loader
        self.historyLoader = historyLoader
        self.refreshLoader = refreshLoader ?? { row, _ in try await loader(row) }
        self.hasMore = !catalog.isEmpty
        super.init()
    }

    deinit {
        loadTask?.cancel()
        retryTask?.cancel()
    }

    /// Suspend optional requests while Home is hidden or the TV is asleep.
    /// Keep the pending batch and cached rows so waking never needs a restart.
    func setActive(_ active: Bool) {
        guard isActive != active else { return }

        isActive = active
        if active {
            resumePendingLoad()
        } else {
            loadGeneration = UUID()
            loadTask?.cancel()
            loadTask = nil
            retryTask?.cancel()
            retryTask = nil
            isWaitingToLoad = false
            isLoading = false
        }
    }

    func resumePendingLoad() {
        guard isActive, loadRequested, loadTask == nil else { return }

        retryTask?.cancel()
        retryTask = nil
        isWaitingToLoad = false
        Task { [weak self] in await self?.loadMore() }
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
        guard hasMore || needsHistory else { return }

        // A visibility callback can arrive before the scene becomes active.
        // Remember its demand so wake can resume it without another scroll.
        loadRequested = true
        guard isActive else { return }

        if let loadTask {
            _ = await loadTask.value
            return
        }
        guard retryTask == nil else { return }

        isLoading = true
        let generation = loadGeneration
        let task = Task { await self.loadBatch() }
        loadTask = task
        let needsRecovery = await task.value
        // A cancelled pre-sleep batch must not clear the task or state of a
        // newer batch that started after wake.
        guard generation == loadGeneration else { return }

        loadTask = nil
        if needsRecovery {
            scheduleRecovery()
        } else {
            loadRequested = false
            consecutiveFailures = 0
        }
        isLoading = false
    }

    private func scheduleRecovery() {
        guard isActive else { return }

        consecutiveFailures += 1
        isWaitingToLoad = true
        let delay = retryDelay(consecutiveFailures)
        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch { return }
            guard !Task.isCancelled, let self, self.isActive else { return }

            self.retryTask = nil
            self.isWaitingToLoad = false
            await self.loadMore()
        }
    }

    private func addHistoryCandidates() async {
        guard needsHistory else { return }
        guard let history = try? await historyLoader() else { return }
        guard !Task.isCancelled else { return }

        needsHistory = false

        let existingIDs = Set(candidates.map(\.id)).union(rows.map(\.id))
        for row in HomeDiscoveryRow.similarRows(recentlyPlayed: history) where !existingIDs.contains(row.id) {
            // Insert only among unseen recipes; loaded rows never move.
            candidates.insert(row, at: Int.random(in: cursor ... candidates.count))
        }
        hasMore = cursor < candidates.count
    }

    /// Returns whether unavailable suggestions are still pending. Failures are
    /// local to these optional rows; they never become a Home error state.
    private func loadBatch() async -> Bool {
        guard !Task.isCancelled else { return true }

        await addHistoryCandidates()
        guard !Task.isCancelled else { return true }

        while cursor < candidates.count {
            guard !Task.isCancelled else { return true }

            let batch = Array(candidates[cursor ..< min(cursor + 3, candidates.count)])
            let results = await withTaskGroup(of: (Int, [BaseItemDto]?).self) { group in
                for (index, definition) in batch.enumerated() {
                    group.addTask { [loader] in
                        guard !Task.isCancelled else { return (index, nil) }

                        return await (index, try? loader(definition))
                    }
                }
                var results: [(Int, [BaseItemDto]?)] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }
            guard !Task.isCancelled else { return true }

            // Preserve the batch across cancellation or a temporary outage.
            // Recovery runs silently, with backoff, while Home is active.
            guard results.contains(where: { $0.1 != nil }) else {
                return true
            }

            cursor += batch.count
            // One failed recipe must not be lost just because its neighbours
            // succeeded. Defer it behind the other unseen categories.
            candidates += results.compactMap { index, items in items == nil ? batch[index] : nil }
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
            hasMore = cursor < candidates.count || needsHistory
            if !validRows.isEmpty {
                return false
            }
            // Empty/sparse rows consume no vertical space; continue looking for
            // a usable batch without exposing their headings or placeholders.
        }
        hasMore = needsHistory
        return needsHistory
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
