import XCTest
@testable import Cosmos

final class GogLibraryMonitorTests: XCTestCase {
    func testParseGameList() throws {
        let json = """
        [{"slug":"celeste","title":"Celeste","exe":"drive_c/GOG Games/Celeste/celeste.exe","exe_source":"scored","exe_score":120}]
        """.data(using: .utf8)!
        let games = GogLibraryMonitor.parseGameList(jsonData: json)
        XCTAssertEqual(games?.count, 1)
        XCTAssertEqual(games?.first?.slug, "celeste")
        XCTAssertEqual(games?.first?.exeSource, "scored")
        XCTAssertEqual(games?.first?.exeScore, 120)
    }

    func testParseSyncOutput() {
        let output = """
        registered slug=celeste title=Celeste
        sync_status=updated
        sync_new=1
        sync_skipped=0
        """
        XCTAssertEqual(GogLibraryMonitor.parseSyncStatus(from: output), "updated")
        XCTAssertEqual(GogLibraryMonitor.parseSyncIntegerField("sync_new", from: output), 1)
        XCTAssertEqual(GogLibraryMonitor.parseSyncIntegerField("sync_skipped", from: output), 0)
    }

    func testUnregisteredFiltersExistingConfigs() throws {
        let games = [
            GogLibraryMonitor.DetectedGame(slug: "celeste", title: "Celeste", exe: "drive_c/x", exeSource: nil, exeScore: nil),
            GogLibraryMonitor.DetectedGame(slug: "hades", title: "Hades", exe: "drive_c/y", exeSource: nil, exeScore: nil),
        ]
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try "APP_NAME=\"Celeste\"\n".write(to: tmp.appendingPathComponent("gog-celeste.conf"), atomically: true, encoding: .utf8)

        let missing = GogLibraryMonitor.unregistered(games: games, configsDirectory: tmp)
        XCTAssertEqual(missing.map(\.slug), ["hades"])
    }
}
