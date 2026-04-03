// pepis-tests/GroupStoreTests.swift
import XCTest
@testable import pepis

final class GroupStoreTests: XCTestCase {

    var tempDir: URL!
    var store: GroupStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        store = GroupStore(supportDir: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStartsEmpty() {
        XCTAssertTrue(store.groups.isEmpty)
    }

    func testSaveAndReload() throws {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertEqual(reloaded.groups.count, 1)
        XCTAssertEqual(reloaded.groups[0].name, "Work")
    }

    func testDeleteGroup() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        store.delete(id: group.id)
        XCTAssertTrue(store.groups.isEmpty)

        let reloaded = GroupStore(supportDir: tempDir)
        XCTAssertTrue(reloaded.groups.isEmpty)
    }

    func testSaveCreatesContextFile() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        let contextURL = store.contextFileURL(for: group)
        XCTAssertTrue(FileManager.default.fileExists(atPath: contextURL.path))
    }

    func testContextFileURLMatchesGroupID() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        let url = store.contextFileURL(for: group)
        XCTAssertEqual(url.lastPathComponent, "\(group.id.uuidString).md")
    }

    func testMalformedJSONStartsEmpty() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let corruptData = "not json".data(using: .utf8)!
        let groupsFile = tempDir.appendingPathComponent("groups.json")
        try corruptData.write(to: groupsFile)

        let store = GroupStore(supportDir: tempDir)
        XCTAssertTrue(store.groups.isEmpty)
    }

    func testOnChangeCalledOnSave() {
        var callCount = 0
        store.onChange = { callCount += 1 }
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        XCTAssertEqual(callCount, 1)
    }

    func testOnChangeCalledOnDelete() {
        let group = Group(id: UUID(), name: "Work", createdAt: Date(), windows: [])
        store.save(group: group)
        var callCount = 0
        store.onChange = { callCount += 1 }
        store.delete(id: group.id)
        XCTAssertEqual(callCount, 1)
    }
}
