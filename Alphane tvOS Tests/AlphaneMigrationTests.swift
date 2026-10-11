//
// SPDX-License-Identifier: MPL-2.0
//

@testable import Alphane
import CoreStore
import Foundation
import XCTest

final class AlphaneMigrationTests: XCTestCase {

    func testProfilesAndSettingsAreCopiedWithoutOverwritingCurrentValues() {
        withSuites { legacyName, currentName in
            let legacy = UserDefaults(suiteName: legacyName)!
            legacy.setPersistentDomain([
                "servers": ["server-id"],
                "users": ["user-id"],
                "lastSignedInUserID": "user-id",
                "appearance": "dark",
                "selectUserServerSelection": UpstreamCompatibility.legacyAllServers
            ], forName: legacyName)
            UserDefaults(suiteName: currentName)!.set("light", forKey: "appearance")

            let current = UpstreamCompatibility.migratedDefaults(suiteName: currentName, legacySuiteName: legacyName)
            XCTAssertEqual(current.stringArray(forKey: "servers"), ["server-id"])
            XCTAssertEqual(current.stringArray(forKey: "users"), ["user-id"])
            XCTAssertEqual(current.string(forKey: "lastSignedInUserID"), "user-id")
            XCTAssertEqual(current.string(forKey: "appearance"), "light")
            XCTAssertEqual(current.string(forKey: "selectUserServerSelection"), SelectUserServerSelection.all.rawValue)
        }
    }

    func testDeletedProfilesAreNotImportedAgain() {
        withSuites { legacyName, currentName in
            UserDefaults(suiteName: legacyName)!.set(["user-id"], forKey: "users")
            let current = UpstreamCompatibility.migratedDefaults(suiteName: currentName, legacySuiteName: legacyName)
            current.removeObject(forKey: "users")
            let repeated = UpstreamCompatibility.migratedDefaults(suiteName: currentName, legacySuiteName: legacyName)
            XCTAssertNil(repeated.object(forKey: "users"))
        }
    }

    func testNewInstallCanMigrateWithoutLegacySettings() {
        withSuites { legacyName, currentName in
            let current = UpstreamCompatibility.migratedDefaults(suiteName: currentName, legacySuiteName: legacyName)
            XCTAssertNil(current.object(forKey: "users"))
        }
    }

    func testDatabaseCopyIncludesJournalAndPreservesTheOriginal() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("old.sqlite")
            let destination = directory.appendingPathComponent("Alphane.sqlite")
            for (index, suffix) in ["", "-wal", "-shm"].enumerated() {
                try Data([UInt8(index)]).write(to: URL(fileURLWithPath: source.path + suffix))
            }
            try UpstreamCompatibility.copyDatabaseIfNeeded(from: source, to: destination)
            for (index, suffix) in ["", "-wal", "-shm"].enumerated() {
                let expected = Data([UInt8(index)])
                XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: source.path + suffix)), expected)
                XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: destination.path + suffix)), expected)
            }
            try Data([9]).write(to: destination)
            try UpstreamCompatibility.copyDatabaseIfNeeded(from: source, to: destination)
            XCTAssertEqual(try Data(contentsOf: destination), Data([9]))
        }
    }

    func testDatabaseOwnersMigrateWithoutReplacingCurrentRecords() throws {
        try withDirectory { directory in
            let stack = DataStack(AlphaneStore.V3.schema)
            try stack.addStorageAndWait(SQLiteStore(fileURL: directory.appendingPathComponent("Alphane.sqlite")))
            try stack.perform { transaction in
                for (owner, field, byte) in [
                    (UpstreamCompatibility.legacyAppSuiteName, "servers", UInt8(1)),
                    (UpstreamCompatibility.legacyAppSuiteName, "users", UInt8(2)),
                    (UpstreamCompatibility.appSuiteName, "users", UInt8(3)),
                    ("user-id", "preferences", UInt8(4))
                ] {
                    let record = transaction.create(Into<AnyStoredData>())
                    record.ownerID = owner
                    record.field = field
                    record.key = field
                    record.data = Data([byte])
                }
            }
            try UpstreamCompatibility.migrateAppOwners(in: stack)
            try UpstreamCompatibility.migrateAppOwners(in: stack)
            let records = try stack.fetchAll(From<AnyStoredData>())
            XCTAssertEqual(records.count, 3)
            XCTAssertFalse(records.contains { $0.ownerID == UpstreamCompatibility.legacyAppSuiteName })
            XCTAssertEqual(records.first { $0.field == "servers" }?.data, Data([1]))
            XCTAssertEqual(records.first { $0.field == "users" }?.data, Data([3]))
            XCTAssertEqual(records.first { $0.field == "preferences" }?.ownerID, "user-id")
        }
    }

    func testCustomProfileArtworkMovesToTheNewDirectory() throws {
        try withDirectory { directory in
            let legacy = directory.appendingPathComponent(UpstreamCompatibility.legacyLocalImageDirectory)
            try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: legacy.appendingPathComponent("avatar"))
            let current = UpstreamCompatibility.localImageDirectory(in: directory)
            XCTAssertEqual(current.lastPathComponent, "com.neogucky.alphane.local")
            XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("avatar")), Data([1, 2, 3]))
            try Data([4]).write(to: current.appendingPathComponent("avatar"))
            XCTAssertEqual(UpstreamCompatibility.localImageDirectory(in: directory), current)
            XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("avatar")), Data([4]))
        }
    }

    private func withSuites(_ work: (String, String) -> Void) {
        let legacyName = "alphane-test-legacy-\(UUID().uuidString)"
        let currentName = "alphane-test-current-\(UUID().uuidString)"
        defer {
            UserDefaults(suiteName: legacyName)!.removePersistentDomain(forName: legacyName)
            UserDefaults(suiteName: currentName)!.removePersistentDomain(forName: currentName)
        }
        work(legacyName, currentName)
    }

    private func withDirectory(_ work: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try work(directory)
    }
}
