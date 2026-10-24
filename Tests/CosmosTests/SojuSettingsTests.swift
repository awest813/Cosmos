import XCTest
@testable import Cosmos

final class SojuSettingsTests: XCTestCase {
    func testLoadSojuModes() {
        let stored = [
            "COSMOS_ROSETTA_AVX": "1",
            "COSMOS_WINE_WRITECOPY": "off"
        ]
        let settings = GraphicsSettingsStore.load(from: stored)
        XCTAssertEqual(settings.rosettaAvx, "on")
        XCTAssertEqual(settings.wineWritecopy, "off")

        let invalid = GraphicsSettingsStore.load(from: ["COSMOS_ROSETTA_AVX": "bogus"])
        XCTAssertEqual(invalid.rosettaAvx, "auto")
        XCTAssertEqual(GraphicsSettings.sojuModeOptions, ["auto", "on", "off"])
    }

    func testParseSojuStatus() {
        let output = """
        Running: run.command --gptk-layout-status

        layout=partial
        copied_so=1
        message=A D3DMetal unix library is a real file. That breaks the Metal loader. Install the layout again to replace it with a symlink.
        """
        let status = GraphicsSettingsStore.parseSojuStatus(output)
        XCTAssertEqual(status.layout, "partial")
        XCTAssertTrue(status.message.contains("symlink"))
    }

    func testSojuSettingLabels() {
        XCTAssertEqual(SettingLabels.displayName(for: "COSMOS_ROSETTA_AVX"), "AVX on Apple Silicon")
        XCTAssertEqual(SettingLabels.displayName(for: "COSMOS_WINE_WRITECOPY"), "Store login page")
    }

    func testSojuOperationTitles() {
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "run.command", arguments: ["--gptk-layout"]),
            "Installing the D3DMetal layout…"
        )
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "run.command", arguments: ["--battlenet-seed"]),
            "Updating Battle.net…"
        )
    }
}
