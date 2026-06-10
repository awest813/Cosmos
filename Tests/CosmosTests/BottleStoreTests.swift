import XCTest
@testable import Cosmos

final class BottleStoreTests: XCTestCase {
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
