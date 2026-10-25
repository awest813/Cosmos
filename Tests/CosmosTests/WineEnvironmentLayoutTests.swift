import XCTest
@testable import Cosmos

final class WineEnvironmentLayoutTests: XCTestCase {
    func testMissingEnvironmentIsDescribedWithoutCreatingIt() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let layout = WineEnvironmentLayout(prefix: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(layout.locations.allSatisfy { !$0.isAvailable })
        XCTAssertTrue(layout.drives.isEmpty)
        XCTAssertTrue(layout.locations.contains { $0.id == "syswow64" })
    }

    func testMappedCDriveAndBrokenExternalDriveAreShownAccurately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appendingPathComponent("prefix")
        let mappings = prefix.appendingPathComponent("dosdevices")
        let external = root.appendingPathComponent("Windows Drive")
        try FileManager.default.createDirectory(at: mappings, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external.appendingPathComponent("users"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: mappings.appendingPathComponent("c:").path, withDestinationPath: external.path)
        try FileManager.default.createSymbolicLink(atPath: mappings.appendingPathComponent("d:").path, withDestinationPath: root.appendingPathComponent("Offline Drive").path)
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        let layout = WineEnvironmentLayout(prefix: prefix)
        XCTAssertEqual(layout.locations.first { $0.id == "drive-c" }?.url.resolvingSymlinksInPath().path, external.resolvingSymlinksInPath().path)
        XCTAssertEqual(layout.locations.first { $0.id == "users" }?.isAvailable, true)
        XCTAssertEqual(layout.drives.first { $0.id == "d:" }?.isAvailable, false)
        XCTAssertEqual(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted(), before)
    }
}
