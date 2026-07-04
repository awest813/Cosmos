import XCTest
@testable import Cosmos

final class GraphicsSettingsTests: XCTestCase {
    func testLoadSyncModeFromConf() {
        let stored = ["COSMOS_SYNC_MODE": "esync", "GPTK_PATH": "/tmp/gptk"]
        let settings = GraphicsSettingsStore.load(from: stored)
        XCTAssertEqual(settings.syncMode, "esync")
        XCTAssertEqual(settings.gptkPath, "/tmp/gptk")
    }

    func testLegacyEsyncInference() {
        let stored = ["WINEESYNC": "1"]
        let settings = GraphicsSettingsStore.load(from: stored)
        XCTAssertEqual(settings.syncMode, "esync")
    }

    func testParseGptkValidationSuccess() {
        let output = """
        valid=1
        path=/GPTK
        dll_dir=/GPTK/lib
        dll_count=12
        """
        let result = GraphicsSettingsStore.parseGptkValidation(output)
        XCTAssertTrue(result.valid)
        XCTAssertEqual(result.dllCount, 12)
        XCTAssertEqual(result.dllDirectory, "/GPTK/lib")
    }

    func testExperimentalChannelNormalizesToLatest() {
        let stored = ["COSMOS_DXMT_CHANNEL": "experimental"]
        let settings = GraphicsSettingsStore.load(from: stored)
        XCTAssertEqual(settings.dxmtChannel, "latest")
    }

    func testParseGptkValidationFailure() {
        let output = """
        valid=0
        path=/bad
        error=Not a directory
        """
        let result = GraphicsSettingsStore.parseGptkValidation(output)
        XCTAssertFalse(result.valid)
        XCTAssertEqual(result.errorMessage, "Not a directory")
    }

    func testLoadSpockD3D9PathFromConf() {
        let stored = ["SPOCK_D3D9_PATH": "/tmp/spockd3d9"]
        let settings = GraphicsSettingsStore.load(from: stored)
        XCTAssertEqual(settings.spockD3D9Path, "/tmp/spockd3d9")
    }

    func testParseSpockD3D9ValidationSuccess() {
        let output = """
        valid=1
        path=/Spock
        dll_count=2
        x86_dll=/Spock/x86/d3d9.dll
        x64_dll=/Spock/x64/d3d9.dll
        """
        let result = GraphicsSettingsStore.parseSpockD3D9Validation(output)
        XCTAssertTrue(result.valid)
        XCTAssertEqual(result.dllCount, 2)
        XCTAssertEqual(result.x86Dll, "/Spock/x86/d3d9.dll")
        XCTAssertTrue(result.summaryText.contains("32-bit"))
    }
}
