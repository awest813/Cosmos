import XCTest
@testable import Cosmos

final class SettingLabelsTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(SettingLabels.displayName(for: "COSMOS_BACKEND"), "Graphics backend")
        XCTAssertEqual(SettingLabels.displayName(for: "COSMOS_STEAM_NATIVE_SCAN"), "Scan native Steam libraries")
    }

    func testSavedMessage() {
        XCTAssertTrue(SettingLabels.savedMessage(for: "COSMOS_BACKEND").contains("Graphics backend"))
    }

    func testBackendDisplayNames() {
        XCTAssertEqual(SettingLabels.backendDisplayName("recommended"), "Recommended")
        XCTAssertEqual(SettingLabels.backendDisplayName("dxmt"), "DXMT")
        XCTAssertEqual(SettingLabels.backendDisplayName("wined3d"), "WineD3D")
    }
}
