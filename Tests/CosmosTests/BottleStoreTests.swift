import XCTest
@testable import Cosmos

final class BottleStoreTests: XCTestCase {
    func testBottleDirectoryMatchesShellOverridesAndLoadsTheCustomEnvironment() throws {
        let originalSupport = ProcessInfo.processInfo.environment["COSMOS_SUPPORT_DIR"]
        let originalBottles = ProcessInfo.processInfo.environment["COSMOS_BOTTLES_DIR"]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let originalSupport { setenv("COSMOS_SUPPORT_DIR", originalSupport, 1) }
            else { unsetenv("COSMOS_SUPPORT_DIR") }
            if let originalBottles { setenv("COSMOS_BOTTLES_DIR", originalBottles, 1) }
            else { unsetenv("COSMOS_BOTTLES_DIR") }
            try? FileManager.default.removeItem(at: root)
        }
        unsetenv("COSMOS_BOTTLES_DIR")
        setenv("COSMOS_SUPPORT_DIR", root.path, 1)
        XCTAssertEqual(BottleStore.bottlesDirectoryURL, root.appendingPathComponent("Bottles", isDirectory: true))
        let custom = root.appendingPathComponent("custom", isDirectory: true)
        setenv("COSMOS_BOTTLES_DIR", custom.path, 1)
        let environment = custom.appendingPathComponent("classic", isDirectory: true)
        try FileManager.default.createDirectory(at: environment, withIntermediateDirectories: true)
        try "COSMOS_BACKEND=\"wined3d\"\n".write(to: environment.appendingPathComponent("bottle.conf"), atomically: true, encoding: .utf8)
        XCTAssertEqual(BottleStore.load().map(\.name), ["classic"])
        XCTAssertEqual(BottleStore.load().first?.prefixURL, environment.appendingPathComponent("prefix", isDirectory: true))
    }

    func testParseConfBasic() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bottle-\(UUID().uuidString).conf")
        defer { try? FileManager.default.removeItem(at: url) }

        let body = """
        # comment
        COSMOS_BACKEND="dxmt"
        WINE_RETINA_MODE=1
        WINDOWS_VERSION=""
        """
        try body.write(to: url, atomically: true, encoding: .utf8)

        let parsed = BottleStore.parseConf(url)
        XCTAssertEqual(parsed["COSMOS_BACKEND"], "dxmt")
        XCTAssertEqual(parsed["WINE_RETINA_MODE"], "1")
        XCTAssertEqual(parsed["WINDOWS_VERSION"], "")
    }

    func testValidBottleNames() {
        XCTAssertTrue(BottleStore.isValidName("steam"))
        XCTAssertTrue(BottleStore.isValidName("game-2"))
        XCTAssertTrue(BottleStore.isValidName("my.bottle"))
    }

    func testInvalidBottleNames() {
        XCTAssertFalse(BottleStore.isValidName(""))
        XCTAssertFalse(BottleStore.isValidName(".."))
        XCTAssertFalse(BottleStore.isValidName("-bad"))
        XCTAssertFalse(BottleStore.isValidName("has space"))
    }
}
