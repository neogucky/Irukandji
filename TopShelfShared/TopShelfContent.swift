//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import TVServices

struct TopShelfEntry: Codable, Equatable {
    let itemID: String
    let title: String
    let contextTitle: String
    let summary: String?
    let duration: TimeInterval?
    let artworkFileName: String
}

struct TopShelfSnapshot: Codable, Equatable {
    let serverID: String
    let userID: String
    let updatedAt: Date
    let entries: [TopShelfEntry]

    func actionURL(itemID: String, play: Bool) -> URL? {
        let components = [serverID, userID, itemID]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard components.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return URL(string: "alphane://\(serverID)/\(userID)/\(play ? "play" : "item")/\(itemID)")
    }
}

/// Only artwork and display metadata are shared. The extension never receives credentials.
struct TopShelfStorage {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    init(appGroupContainer: URL) {
        // Physical tvOS permits cache writes within Library/Caches; the
        // app-group root can appear writable in the simulator alone.
        self.directory = appGroupContainer.appendingPathComponent("Library/Caches/TopShelf", isDirectory: true)
    }

    static var shared: Self? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AlphaneAppGroup") as? String,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return nil }
        return Self(appGroupContainer: container)
    }

    private var manifest: URL { directory.appendingPathComponent("content.json") }

    func read() -> TopShelfSnapshot? {
        guard let data = try? Data(contentsOf: manifest) else { return nil }
        return try? JSONDecoder().decode(TopShelfSnapshot.self, from: data)
    }

    func activate(serverID: String, userID: String) throws {
        if let snapshot = read(), snapshot.serverID == serverID, snapshot.userID == userID { return }
        try clear()
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func artworkURL(fileName: String) -> URL? {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              fileName.hasSuffix(".jpg"), !fileName.hasPrefix(".") else { return nil }
        return directory.appendingPathComponent(fileName)
    }

    func write(_ snapshot: TopShelfSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: manifest, options: .atomic)
        // Keep previous images briefly: tvOS may still be displaying an earlier snapshot.
        let keep = Set(snapshot.entries.map(\.artworkFileName))
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        for file in files where file.pathExtension == "jpg" && !keep.contains(file.lastPathComponent) {
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            if modified < Date.now.addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
        }
    }

    func carousel(now: Date = .now) -> TVTopShelfCarouselContent? {
        guard let snapshot = read(), snapshot.updatedAt.addingTimeInterval(7 * 86400) > now else { return nil }
        let items = snapshot.entries.prefix(8).compactMap { entry -> TVTopShelfCarouselItem? in
            guard let image = artworkURL(fileName: entry.artworkFileName),
                  FileManager.default.fileExists(atPath: image.path),
                  let displayURL = snapshot.actionURL(itemID: entry.itemID, play: false),
                  let playURL = snapshot.actionURL(itemID: entry.itemID, play: true) else { return nil }
            let item = TVTopShelfCarouselItem(identifier: "\(snapshot.serverID)-\(snapshot.userID)-\(entry.itemID)")
            item.title = entry.title
            item.contextTitle = entry.contextTitle
            item.summary = entry.summary
            item.duration = entry.duration ?? 0
            item.expirationDate = snapshot.updatedAt.addingTimeInterval(7 * 86400)
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
            item.displayAction = TVTopShelfAction(url: displayURL)
            item.playAction = TVTopShelfAction(url: playURL)
            return item
        }
        return items.isEmpty ? nil : TVTopShelfCarouselContent(style: .details, items: items)
    }
}
