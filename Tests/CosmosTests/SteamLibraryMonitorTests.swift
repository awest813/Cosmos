import XCTest
@testable import Cosmos

final class SteamLibraryMonitorTests: XCTestCase {
    func testParseGameListJSON() {
        let json = """
        [{"appid":"730","name":"Counter-Strike 2"},{"appid":"440","name":"Team Fortress 2"}]
        """.data(using: .utf8)!
        let games = SteamLibraryMonitor.parseGameList(jsonData: json)
        XCTAssertEqual(games?.count, 2)
        XCTAssertEqual(games?.first?.appID, "730")
    }

    func testNewGamesComparedToSnapshot() {
        let current = [
            SteamLibraryMonitor.DetectedGame(appID: "730", name: "CS2"),
            SteamLibraryMonitor.DetectedGame(appID: "440", name: "TF2"),
        ]
        let snapshot: Set<String> = ["730"]
        let fresh = SteamLibraryMonitor.newGames(comparedTo: snapshot, current: current)
        XCTAssertEqual(fresh.map(\.appID), ["440"])
    }

    func testParseSyncStatus() {
        let output = "sync_status=updated\nsync_new=2\nsync_removed=1\n"
        XCTAssertEqual(SteamLibraryMonitor.parseSyncStatus(from: output), "updated")
        XCTAssertEqual(SteamLibraryMonitor.parseSyncNewCount(from: output), 2)
        XCTAssertEqual(SteamLibraryMonitor.parseSyncRemovedCount(from: output), 1)
    }

    func testSyncResultSucceeded() {
        let ok = SteamLibraryMonitor.SyncResult(status: "updated", newCount: 1, exitCode: 0, output: "")
        XCTAssertTrue(ok.succeeded)
        let failed = SteamLibraryMonitor.SyncResult(status: "failed", newCount: 0, exitCode: 1, output: "")
        XCTAssertFalse(failed.succeeded)
        let seeded = SteamLibraryMonitor.SyncResult(status: "seeded", newCount: 0, exitCode: 0, output: "")
        XCTAssertTrue(seeded.succeeded)
    }
}
