import XCTest
@testable import Cosmos

final class GogLibraryMonitorTests: XCTestCase {
    func testParseGameList() throws {
        let json = """
        [{"slug":"celeste","title":"Celeste","exe":"drive_c/GOG Games/Celeste/celeste.exe"}]
        """.data(using: .utf8)!
        let games = GogLibraryMonitor.parseGameList(jsonData: json)
        XCTAssertEqual(games?.count, 1)
        XCTAssertEqual(games?.first?.slug, "celeste")
    }

    func testUnregisteredFiltersExistingConfigs() throws {
        let games = [
            GogLibraryMonitor.DetectedGame(slug: "celeste", title: "Celeste", exe: "drive_c/x"),
            GogLibraryMonitor.DetectedGame(slug: "hades", title: "Hades", exe: "drive_c/y"),
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
