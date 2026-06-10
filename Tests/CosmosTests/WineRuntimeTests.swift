import XCTest
@testable import Cosmos

final class WineRuntimeTests: XCTestCase {
    func testParseRuntimeStatusLines() {
        let text = """
        chip=arm64
        rosetta=available
        wine_version=11.8
        wine_installed=1
        wine_root=/Users/test/wine-11.8
        wine_bin=/Users/test/wine-11.8/Wine Devel.app/Contents/Resources/wine/bin/wine
        wine_report=wine-11.8
        """
        let status = WineRuntimeStore.parseStatusLines(text, fallbackWineVersion: "11.8")
        XCTAssertNotNil(status)
        XCTAssertEqual(status?.chipArchitecture, "arm64")
        XCTAssertEqual(status?.rosettaCode, "available")
        XCTAssertTrue(status?.rosettaReady == true)
        XCTAssertTrue(status?.wineInstalled == true)
        XCTAssertEqual(status?.wineVersion, "11.8")
    }

    func testRosettaMissingBlocksLaunchReadiness() {
        let status = WineRuntimeStatus(
            chipArchitecture: "arm64",
            rosettaCode: "missing",
            wineVersion: "11.8",
            wineInstalled: true,
            wineRootPath: "/tmp/wine",
            wineBinaryPath: "/tmp/wine/bin/wine",
            wineReportedVersion: nil
        )
        XCTAssertTrue(status.needsRosetta)
        XCTAssertFalse(status.rosettaReady)
        XCTAssertFalse(status.isLaunchReady)
    }

    func testIntelHostSkipsRosetta() {
        let status = WineRuntimeStatus(
            chipArchitecture: "x86_64",
            rosettaCode: "not_required",
            wineVersion: "11.8",
            wineInstalled: false,
            wineRootPath: "",
            wineBinaryPath: "",
            wineReportedVersion: nil
        )
        XCTAssertFalse(status.needsRosetta)
        XCTAssertTrue(status.rosettaReady)
        XCTAssertTrue(status.canStartWineLaunch)
        XCTAssertEqual(status.platformDisplayName, "Intel")
        XCTAssertTrue(status.translationNote.contains("without Rosetta"))
    }

    func testIntelHostLaunchReadyWhenWineInstalled() {
        let status = WineRuntimeStatus(
            chipArchitecture: "x86_64",
            rosettaCode: "not_required",
            wineVersion: "11.8",
            wineInstalled: true,
            wineRootPath: "/tmp/wine",
            wineBinaryPath: "/tmp/wine/bin/wine",
            wineReportedVersion: "wine-11.8"
        )
        XCTAssertTrue(status.isLaunchReady)
        XCTAssertEqual(status.platformDisplayName, "Intel")
    }

    func testAppleSiliconPlatformLabel() {
        let status = WineRuntimeStatus(
            chipArchitecture: "arm64",
            rosettaCode: "available",
            wineVersion: "11.8",
            wineInstalled: true,
            wineRootPath: "/tmp/wine",
            wineBinaryPath: "/tmp/wine/bin/wine",
            wineReportedVersion: nil
        )
        XCTAssertEqual(status.platformDisplayName, "Apple Silicon")
        XCTAssertTrue(status.canStartWineLaunch)
    }
}
