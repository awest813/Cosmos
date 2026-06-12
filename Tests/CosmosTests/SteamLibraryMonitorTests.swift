import XCTest
@testable import Cosmos

final class SteamLibraryMonitorTests: XCTestCase {
    func testParseGameListJSON() {
        let json = """
        [{"appid":"730","name":"Counter-Strike 2","sync_eligible":true,"install_status":"ok"}]
        """.data(using: .utf8)!
        let games = SteamLibraryMonitor.parseGameList(jsonData: json)
        XCTAssertEqual(games?.count, 1)
        XCTAssertEqual(games?.first?.appID, "730")
        XCTAssertEqual(games?.first?.syncEligible, true)
    }

    func testParseNativeOnlyGameJSON() {
        let json = """
        [{"appid":"620","name":"Portal 2","install_status":"native_only","sync_eligible":false,"source":"native only"}]
        """.data(using: .utf8)!
        let games = SteamLibraryMonitor.parseGameList(jsonData: json)
        XCTAssertEqual(games?.first?.installStatus, "native_only")
        XCTAssertEqual(games?.first?.syncEligible, false)
        XCTAssertFalse(SteamLibraryMonitor.isWineManaged(games!.first!))
        XCTAssertFalse(SteamLibraryMonitor.isSyncEligible(games!.first!))
        XCTAssertTrue(SteamLibraryMonitor.brokenInstalls(in: games!).isEmpty)
    }

    func testNewGamesComparedToSnapshot() {
        let current = [
            SteamLibraryMonitor.DetectedGame(
                appID: "730", name: "CS2", installdirOK: true, exeOK: true,
                gameExe: nil, installStatus: "ok", source: nil, syncEligible: true
            ),
            SteamLibraryMonitor.DetectedGame(
                appID: "440", name: "TF2", installdirOK: false, exeOK: false,
                gameExe: nil, installStatus: "missing_installdir", source: nil, syncEligible: false
            ),
        ]
        let snapshot: Set<String> = ["730"]
        let fresh = SteamLibraryMonitor.newGames(comparedTo: snapshot, current: current)
        XCTAssertEqual(fresh.map(\.appID), ["440"])
    }

    func testSyncEligibleNewGamesSkipsBrokenAndNative() {
        let current = [
            SteamLibraryMonitor.DetectedGame(
                appID: "100", name: "New OK", installdirOK: true, exeOK: true,
                gameExe: "x", installStatus: "ok", source: nil, syncEligible: true
            ),
            SteamLibraryMonitor.DetectedGame(
                appID: "200", name: "New Broken", installdirOK: false, exeOK: false,
                gameExe: nil, installStatus: "missing_installdir", source: nil, syncEligible: false
            ),
            SteamLibraryMonitor.DetectedGame(
                appID: "300", name: "Native", installdirOK: nil, exeOK: nil,
                gameExe: nil, installStatus: "native_only", source: "native only", syncEligible: false
            ),
        ]
        let eligible = SteamLibraryMonitor.syncEligibleNewGames(comparedTo: [], current: current)
        XCTAssertEqual(eligible.map(\.appID), ["100"])
    }

    func testParseSyncStatus() {
        let output = "sync_status=updated\nsync_new=2\nsync_removed=1\n"
        XCTAssertEqual(SteamLibraryMonitor.parseSyncStatus(from: output), "updated")
        XCTAssertEqual(SteamLibraryMonitor.parseSyncNewCount(from: output), 2)
        XCTAssertEqual(SteamLibraryMonitor.parseSyncRemovedCount(from: output), 1)
    }

    func testSyncResultSucceeded() {
        let ok = SteamLibraryMonitor.SyncResult(
            status: "updated", newCount: 1, removedCount: 0, exitCode: 0, output: ""
        )
        XCTAssertTrue(ok.succeeded)
        let failed = SteamLibraryMonitor.SyncResult(
            status: "failed", newCount: 0, removedCount: 0, exitCode: 1, output: ""
        )
        XCTAssertFalse(failed.succeeded)
        let seeded = SteamLibraryMonitor.SyncResult(
            status: "seeded", newCount: 0, removedCount: 0, exitCode: 0, output: ""
        )
        XCTAssertTrue(seeded.succeeded)
    }

    func testBrokenInstallsFilter() {
        let games = [
            SteamLibraryMonitor.DetectedGame(
                appID: "570", name: "Dota", installdirOK: true, exeOK: true,
                gameExe: "drive_c/x", installStatus: "ok", source: nil, syncEligible: true
            ),
            SteamLibraryMonitor.DetectedGame(
                appID: "123", name: "Broken", installdirOK: false, exeOK: false,
                gameExe: nil, installStatus: "missing_installdir", source: nil, syncEligible: false
            ),
            SteamLibraryMonitor.DetectedGame(
                appID: "620", name: "Portal 2", installdirOK: nil, exeOK: nil,
                gameExe: nil, installStatus: "native_only", source: "native only", syncEligible: false
            ),
        ]
        XCTAssertEqual(SteamLibraryMonitor.brokenInstalls(in: games).map(\.appID), ["123"])
    }

    func testSnapshotURLUsesSupportDirectory() throws {
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-snapshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        setenv("COSMOS_SUPPORT_DIR", support.path, 1)
        defer {
            unsetenv("COSMOS_SUPPORT_DIR")
            try? FileManager.default.removeItem(at: support)
        }
        XCTAssertEqual(
            SteamLibraryMonitor.snapshotURL().path,
            support.appendingPathComponent("steam-library.snapshot").path
        )
        XCTAssertEqual(
            SteamLibraryMonitor.snapshotURL(bottleName: "Main").path,
            support.appendingPathComponent("steam-library.Main.snapshot").path
        )
    }
}
