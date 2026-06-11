import XCTest
@testable import Cosmos

final class ProfilePreferencesStoreTests: XCTestCase {
    private var supportDir: URL!

    override func setUpWithError() throws {
        supportDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-prefs-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        setenv("COSMOS_SUPPORT_DIR", supportDir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("COSMOS_SUPPORT_DIR")
        try? FileManager.default.removeItem(at: supportDir)
    }

    func testToggleFavorite() {
        var prefs = ProfilePreferencesStore.toggleFavorite(profileID: "steam-730.conf")
        XCTAssertTrue(ProfilePreferencesStore.isFavorite(profileID: "steam-730.conf", in: prefs))
        prefs = ProfilePreferencesStore.toggleFavorite(profileID: "steam-730.conf")
        XCTAssertFalse(ProfilePreferencesStore.isFavorite(profileID: "steam-730.conf", in: prefs))
    }

    func testRecentLaunchOrdering() {
        _ = ProfilePreferencesStore.recordRecentLaunch(profileID: "a.conf")
        _ = ProfilePreferencesStore.recordRecentLaunch(profileID: "b.conf")
        var prefs = ProfilePreferencesStore.recordRecentLaunch(profileID: "a.conf")
        XCTAssertEqual(prefs.recentIDs.prefix(2).map { String($0) }, ["a.conf", "b.conf"])
    }

    func testPruneStaleProfileIDs() {
        _ = ProfilePreferencesStore.toggleFavorite(profileID: "gone.conf")
        _ = ProfilePreferencesStore.recordRecentLaunch(profileID: "keep.conf")
        let prefs = ProfilePreferencesStore.prune(validProfileIDs: ["keep.conf"])
        XCTAssertFalse(ProfilePreferencesStore.isFavorite(profileID: "gone.conf", in: prefs))
        XCTAssertEqual(prefs.recentIDs, ["keep.conf"])
    }
}
