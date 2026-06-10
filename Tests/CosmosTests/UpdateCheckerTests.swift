import XCTest
@testable import Cosmos

final class UpdateCheckerTests: XCTestCase {
    func testParsesUpdateAvailableJSON() {
        let json = """
        {
          "app_version": "0.7.0",
          "runtime_version": "1.1.0-preview",
          "latest_release": "0.7.1",
          "status": "update_available"
        }
        """.data(using: .utf8)!

        let status = UpdateChecker.parse(jsonData: json, exitCode: 2)
        XCTAssertEqual(status?.appVersion, "0.7.0")
        XCTAssertEqual(status?.latestRelease, "0.7.1")
        XCTAssertEqual(status?.state, .updateAvailable)
        XCTAssertTrue(status?.updateAvailable == true)
    }

    func testParsesCurrentJSON() {
        let json = """
        {
          "app_version": "0.7.1",
          "runtime_version": "1.1.0-preview",
          "latest_release": "0.7.1",
          "status": "current"
        }
        """.data(using: .utf8)!

        let status = UpdateChecker.parse(jsonData: json, exitCode: 0)
        XCTAssertEqual(status?.state, .current)
        XCTAssertFalse(status?.updateAvailable == true)
    }
}
