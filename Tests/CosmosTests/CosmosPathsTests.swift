import XCTest
@testable import Cosmos

final class CosmosPathsTests: XCTestCase {
    private var supportDir: URL!

    override func setUpWithError() throws {
        supportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-paths-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        setenv("COSMOS_SUPPORT_DIR", supportDir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("COSMOS_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: supportDir)
    }

    func testSupportDirectoryOverride() {
        XCTAssertEqual(CosmosPaths.supportDirectory.path, supportDir.path)
        XCTAssertEqual(CosmosPaths.userProfilesDirectory.path, supportDir.appendingPathComponent("Profiles").path)
        XCTAssertEqual(CosmosPaths.userConfigsDirectory.path, supportDir.appendingPathComponent("cosmos_configs").path)
        XCTAssertEqual(
            CosmosPaths.defaultSpockD3D9Directory.path,
            supportDir.appendingPathComponent("Runtime/spockd3d9").path
        )
    }
}
