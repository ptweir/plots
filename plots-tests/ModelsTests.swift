// pepis-tests/ModelsTests.swift
import XCTest
@testable import pepis

final class ModelsTests: XCTestCase {

    func testWindowSnapshotCodableRoundTrip() throws {
        let snapshot = WindowSnapshot(
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            windowIndex: 0,
            frame: CGRect(x: 100, y: 200, width: 1200, height: 800)
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WindowSnapshot.self, from: data)
        XCTAssertEqual(decoded.appBundleID, "com.apple.Safari")
        XCTAssertEqual(decoded.appName, "Safari")
        XCTAssertEqual(decoded.windowIndex, 0)
        XCTAssertEqual(decoded.frame, CGRect(x: 100, y: 200, width: 1200, height: 800))
    }

    func testGroupCodableRoundTrip() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000000)
        let snapshot = WindowSnapshot(
            appBundleID: "com.apple.Terminal",
            appName: "Terminal",
            windowIndex: 1,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        let group = Group(id: id, name: "Morning setup", createdAt: date, windows: [snapshot])
        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(Group.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Morning setup")
        XCTAssertEqual(decoded.createdAt, date)
        XCTAssertEqual(decoded.windows.count, 1)
        XCTAssertEqual(decoded.windows[0].appBundleID, "com.apple.Terminal")
    }
}
