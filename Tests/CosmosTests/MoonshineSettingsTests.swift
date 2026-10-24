import XCTest
@testable import Cosmos

final class MoonshineSettingsTests: XCTestCase {
    func testLoadWineDebugPreset() {
        let detailed = GraphicsSettingsStore.load(from: ["COSMOS_WINEDEBUG_PRESET": "moonshine"])
        XCTAssertEqual(detailed.wineDebugPreset, "moonshine")

        let quiet = GraphicsSettingsStore.load(from: ["COSMOS_WINEDEBUG_PRESET": "nope"])
        XCTAssertEqual(quiet.wineDebugPreset, "cosmos")
    }

    func testParseOpenGLStatus() {
        let output = """
        Running: run.command --opengl-status

        status=unpatched
        path=/tmp/winemac.so
        offset=207355
        byte=74
        message=OpenGL 3.2 check is still the original jump. Cosmos can flip it.
        """
        let status = GraphicsSettingsStore.parseOpenGLStatus(output)
        XCTAssertEqual(status.status, "unpatched")
        XCTAssertEqual(status.path, "/tmp/winemac.so")
        XCTAssertEqual(status.offset, "207355")
        XCTAssertEqual(status.byte, "74")
        XCTAssertTrue(status.message.contains("original jump"))
    }

    func testWineLogLabel() {
        XCTAssertEqual(SettingLabels.displayName(for: "COSMOS_WINEDEBUG_PRESET"), "Wine log detail")
    }

    func testOpenGLOperationTitles() {
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "run.command", arguments: ["--opengl-status"]),
            "Checking the OpenGL fix…"
        )
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "run.command", arguments: ["--opengl-patch"]),
            "Applying the OpenGL fix…"
        )
        XCTAssertEqual(
            CosmosOperationLabel.title(script: "run.command", arguments: ["--opengl-revert"]),
            "Removing the OpenGL fix…"
        )
    }
}
