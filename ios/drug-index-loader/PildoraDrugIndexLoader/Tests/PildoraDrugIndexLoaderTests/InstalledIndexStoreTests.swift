import Foundation
import XCTest

@testable import PildoraDrugIndexLoader

final class InstalledIndexStoreTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testStartsEmpty() throws {
        let store = try InstalledIndexStore(directory: dir)
        XCTAssertFalse(store.hasInstalledFullIndex())
        XCTAssertNil(store.installedVersion())
    }

    func testInstallRecordsVersionAndContents() throws {
        let store = try InstalledIndexStore(directory: dir)
        let temp = dir.appendingPathComponent("incoming.db")
        try Data("index-bytes-v1".utf8).write(to: temp)

        try store.install(databaseAt: temp, version: "2026.07.02")

        XCTAssertTrue(store.hasInstalledFullIndex())
        XCTAssertEqual(store.installedVersion(), "2026.07.02")
        XCTAssertEqual(
            try Data(contentsOf: store.installedFullIndexURL),
            Data("index-bytes-v1".utf8)
        )
        // The temp source is consumed by the atomic move.
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
    }

    func testReinstallReplacesAtomically() throws {
        let store = try InstalledIndexStore(directory: dir)

        let first = dir.appendingPathComponent("v1.db")
        try Data("v1".utf8).write(to: first)
        try store.install(databaseAt: first, version: "2026.01.01")

        let second = dir.appendingPathComponent("v2.db")
        try Data("v2-newer".utf8).write(to: second)
        try store.install(databaseAt: second, version: "2026.09.09")

        XCTAssertEqual(store.installedVersion(), "2026.09.09")
        XCTAssertEqual(try Data(contentsOf: store.installedFullIndexURL), Data("v2-newer".utf8))
    }

    func testRemoveInstalled() throws {
        let store = try InstalledIndexStore(directory: dir)
        let temp = dir.appendingPathComponent("incoming.db")
        try Data("bytes".utf8).write(to: temp)
        try store.install(databaseAt: temp, version: "2026.07.02")

        try store.removeInstalled()
        XCTAssertFalse(store.hasInstalledFullIndex())
        XCTAssertNil(store.installedVersion())
    }
}
