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

/// A small in-memory cache of complete searches, scoped to one authenticated session.
@MainActor
final class SearchResultCache {

    struct Row {
        let id: String
        let title: String
        let displayType: PosterDisplayType
        let items: [ItemEntry]
    }

    private struct Snapshot {
        let query: String
        let rows: [Row]
        let recordedAt: Date
        let titles: [String: [String?]]
    }

    private weak var session: UserSession?
    private var serverURL: URL?
    private var snapshots: [Snapshot] = []
    private var storeChanges: AnyCancellable?
    private(set) var revision: UInt = 0
    private(set) var lastRefinementDate: Date?
    private let lifetime: TimeInterval
    private let now: () -> Date

    init(lifetime: TimeInterval = 300, now: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime
        self.now = now
    }

    func clear() {
        revision &+= 1
        lastRefinementDate = nil
        snapshots.removeAll()
    }

    func prepare(session: UserSession) {
        bind(to: session)
    }

    func store(query: String, rows: [Row], session: UserSession, recordedAt: Date? = nil) {
        bind(to: session)
        let query = Self.normalizedQuery(query)
        let recordedAt = recordedAt ?? now()
        guard session.items.isActive, Self.supportsLocalMatching(query),
              now().timeIntervalSince(recordedAt) < lifetime,
              rows.flatMap(\.items).allSatisfy({ Self.matches($0.snapshot, query: query) }),
              rows.reduce(0, { $0 + $1.items.count }) <= 2000 else { return }

        snapshots.removeAll { $0.query == query || now().timeIntervalSince($0.recordedAt) >= lifetime }
        let titles = Dictionary(
            rows.flatMap(\.items).map { ($0.itemID, Self.titles($0.snapshot)) },
            uniquingKeysWith: { _, latest in latest }
        )
        snapshots.append(.init(query: query, rows: rows, recordedAt: recordedAt, titles: titles))
        if snapshots.count > 4 {
            snapshots.removeFirst(snapshots.count - 4)
        }
    }

    /// nil means a server request is required; an empty set of rows is a valid local result.
    func refinedRows(query: String, session: UserSession) -> [Row]? {
        bind(to: session)
        lastRefinementDate = nil
        let query = Self.normalizedQuery(query)
        guard session.items.isActive, Self.supportsLocalMatching(query) else { return nil }

        snapshots.removeAll { now().timeIntervalSince($0.recordedAt) >= lifetime }

        // Preserve accents in the containment check: removing an accent can broaden
        // matches against OriginalTitle even when the cleaned title is unchanged.
        guard let source = snapshots.reversed().first(where: { query.contains($0.query) }),
              source.rows.allSatisfy({ $0.items.allSatisfy { $0.value != nil } }) else { return nil }

        // Search-provider versions differ on custom sort-title aliases. Ask the
        // server when one would change the narrowed result instead of guessing.
        if source.rows.flatMap(\.items).contains(where: {
            !Self.matches($0.snapshot, query: query) && Self.cleaned($0.snapshot.sortName ?? "").contains(Self.cleaned(query))
        }) {
            return nil
        }

        lastRefinementDate = source.recordedAt
        return source.rows.map { row in
            let filtered = row.items
                .enumerated()
                .filter { Self.matches($0.element.snapshot, query: query) }
                .sorted { lhs, rhs in
                    let left = Self.rank(lhs.element.snapshot, query: query)
                    let right = Self.rank(rhs.element.snapshot, query: query)
                    if left != right {
                        return left < right
                    }
                    let leftName = Self.cleaned(lhs.element.snapshot.sortName ?? lhs.element.snapshot.name ?? "")
                    let rightName = Self.cleaned(rhs.element.snapshot.sortName ?? rhs.element.snapshot.name ?? "")
                    return leftName == rightName ? lhs.offset < rhs.offset : leftName < rightName
                }
                .map(\.element)
            return Row(id: row.id, title: row.title, displayType: row.displayType, items: filtered)
        }
    }

    static func normalizedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func supportsLocalMatching(_ query: String) -> Bool {
        !query.isEmpty && query.rangeOfCharacter(from: CharacterSet(charactersIn: "%_[]^")) == nil
    }

    private static func cleaned(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    private static func matches(_ item: BaseItemDto, query: String) -> Bool {
        let cleanedQuery = cleaned(query)
        return cleaned(item.name ?? "").contains(cleanedQuery) ||
            item.originalTitle?.lowercased().contains(query) == true
    }

    private static func rank(_ item: BaseItemDto, query: String) -> Int {
        let name = cleaned(item.name ?? "")
        let query = cleaned(query)
        if name == query {
            return 0
        }
        if name.hasPrefix(query + " ") {
            return 1
        }
        if name.hasPrefix(query) {
            return 2
        }
        return 3
    }

    private func bind(to session: UserSession) {
        if self.session !== session || serverURL != session.client.configuration.url {
            clear()
            self.session = session
            serverURL = session.client.configuration.url
            storeChanges = session.items.changes.sink { [weak self, weak session] change in
                guard let self else { return }

                switch change {
                case .libraryChanged, .deleted, .invalidated:
                    self.clear()
                case let .updated(update):
                    guard update.metadataChanged,
                          let item = session?.items[update.itemID]?.value else { return }

                    if self.snapshots.contains(where: {
                        $0.titles[update.itemID].map { $0 != Self.titles(item) } == true
                    }) {
                        self.clear()
                    }
                }
            }
        }
    }

    private static func titles(_ item: BaseItemDto) -> [String?] {
        [item.name, item.originalTitle, item.sortName]
    }
}
