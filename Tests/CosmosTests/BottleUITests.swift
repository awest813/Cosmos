import XCTest
@testable import Cosmos

final class BottleUITests: XCTestCase {
    private func sampleBottle(
        settings: [String: String] = [:],
        initialized: Bool = true,
        steam: Bool = false
    ) -> Bottle {
        Bottle(
            id: "retro",
            settings: settings,
            prefixURL: URL(fileURLWithPath: "/tmp/Bottles/retro/prefix"),
            isInitialized: initialized,
            steamInstalled: steam
        )
    }

    func testStatusKind() {
        XCTAssertEqual(sampleBottle(initialized: false).statusKind, .notCreated)
        XCTAssertEqual(sampleBottle(initialized: true, steam: false).statusKind, .initialized)
        XCTAssertEqual(sampleBottle(initialized: true, steam: true).statusKind, .steamReady)
    }

    func testCardDetailLineIncludesBackendSettings() {
        let bottle = sampleBottle(settings: [
            "COSMOS_BACKEND": "dxmt",
            "WINDOWS_VERSION": "win10",
            "COSMOS_SYNC_MODE": "esync",
            "WINE_RETINA_MODE": "1",
        ])
        XCTAssertEqual(bottle.backendDisplayName, "DXMT")
        XCTAssertTrue(bottle.cardDetailLine.contains("Windows 10"))
        XCTAssertTrue(bottle.cardDetailLine.contains("Esync"))
        XCTAssertTrue(bottle.cardDetailLine.contains("Retina"))
        XCTAssertTrue(bottle.cardDetailLine.contains("64-bit and 32-bit"))
        XCTAssertEqual(SettingLabels.prefixArchDisplayName("win32"), "32-bit only")
        XCTAssertEqual(
            sampleBottle(settings: ["COSMOS_PREFIX_ARCH": "win64"]).prefixArch,
            "win64"
        )
    }

    func testConfigURL() {
        let bottle = sampleBottle()
        XCTAssertEqual(bottle.configURL.lastPathComponent, "bottle.conf")
        XCTAssertTrue(bottle.configURL.path.hasSuffix("/Bottles/retro/bottle.conf"))
    }
}
