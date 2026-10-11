//
// Alphane is based on Swiftfin by Jellyfin and its contributors.
// The legacy identifiers below are read only to preserve existing installations.
// SPDX-License-Identifier: MPL-2.0
//

import CoreStore
import Foundation

/// Compatibility with persisted data from Swiftfin and earlier Alphane builds.
enum UpstreamCompatibility {

    static let appSuiteName = "alphaneApp"
    static let legacyAppSuiteName = "swiftfinApp"
    static let legacyDatabaseName = "Swiftfin.sqlite"
    static let legacyAllServers = "swiftfin-all"
    static let legacyLocalImageDirectory = "Caches/org.jellyfin.swiftfin.local"
    static let upstreamClientName = "swiftfin"

    static func appDefaults() -> UserDefaults {
        migratedDefaults(suiteName: appSuiteName, legacySuiteName: legacyAppSuiteName)
    }

    static func debugDefaults() -> UserDefaults {
        migratedDefaults(suiteName: "alphanestore-debug-defaults", legacySuiteName: "swiftfinstore-debug-defaults")
    }

    /// Copy only owned values, preserving any settings already written by Alphane.
    /// The marker prevents removed profiles or reset settings from being imported again.
    static func migratedDefaults(suiteName: String, legacySuiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        let marker = "alphaneStorageMigrationComplete"
        var values = defaults.persistentDomain(forName: suiteName) ?? [:]
        guard values[marker] as? Bool != true else { return defaults }

        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!
        let legacyValues = legacyDefaults.persistentDomain(forName: legacySuiteName) ?? [:]
        values = legacyValues.merging(values) { _, current in current }
        for key in ["selectUserServerSelection", "selectUserAllServersSplashscreen"] {
            if values[key] as? String == legacyAllServers {
                values[key] = "alphane-all"
            }
        }
        values[marker] = true
        defaults.setPersistentDomain(values, forName: suiteName)
        return defaults
    }

    /// Stage SQLite and its journal together before publishing the renamed database.
    /// The source remains untouched in case opening or migrating the copy fails.
    static func copyDatabaseIfNeeded(from source: URL, to destination: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path), manager.fileExists(atPath: source.path) else { return }

        let directory = destination.deletingLastPathComponent()
        let staging = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: staging) }

        let suffixes = ["-shm", "-wal", ""]
        for suffix in suffixes {
            let artifact = URL(fileURLWithPath: source.path + suffix)
            if manager.fileExists(atPath: artifact.path) {
                try manager.copyItem(at: artifact, to: staging.appendingPathComponent(destination.lastPathComponent + suffix))
            }
        }
        var published: [URL] = []
        do {
            for suffix in suffixes {
                let staged = staging.appendingPathComponent(destination.lastPathComponent + suffix)
                if manager.fileExists(atPath: staged.path) {
                    let target = URL(fileURLWithPath: destination.path + suffix)
                    if manager.fileExists(atPath: target.path) {
                        try manager.removeItem(at: target)
                    }
                    try manager.moveItem(at: staged, to: target)
                    published.append(target)
                }
            }
        } catch {
            for artifact in published {
                try? manager.removeItem(at: artifact)
            }
            throw error
        }
    }

    static func migrateAppOwners(in stack: DataStack) throws {
        try stack.perform { transaction in
            let legacy = try transaction.fetchAll(
                From<AnyStoredData>().where(\.$ownerID == legacyAppSuiteName)
            )
            for value in legacy {
                let existing = try transaction.fetchAll(
                    From<AnyStoredData>().where(
                        \.$ownerID == appSuiteName && \.$field == value.field && \.$key == value.key
                    )
                )
                if existing.isEmpty {
                    transaction.edit(value)?.ownerID = appSuiteName
                } else {
                    transaction.delete(value)
                }
            }
        }
    }

    static func localImageDirectory(in root: URL) -> URL {
        let destination = root.appendingPathComponent("Caches/com.neogucky.alphane.local", isDirectory: true)
        let source = root.appendingPathComponent(legacyLocalImageDirectory, isDirectory: true)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path), manager.fileExists(atPath: source.path) else {
            return destination
        }

        do {
            try manager.copyItem(at: source, to: destination)
            return destination
        } catch {
            // Keep custom avatars available even if the cache cannot be copied yet.
            return source
        }
    }
}
