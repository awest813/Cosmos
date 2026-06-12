import XCTest
@testable import Cosmos

final class GameProfileWriterTests: XCTestCase {
    func testBuildGOGYAML() throws {
        let yaml = try GameProfileWriter.buildGOGYAML(
            name: "Celeste",
            slug: "celeste",
            exePath: "drive_c/GOG Games/Celeste/celeste.exe"
        )
        XCTAssertTrue(yaml.contains("store: gog"))
        XCTAssertTrue(yaml.contains("gog_slug: celeste"))
        XCTAssertTrue(yaml.contains("exe_path: drive_c/GOG Games/Celeste/celeste.exe"))
    }

    func testSuggestedSteamFilename() {
        let yaml = """
        id: civ6
        name: "Civilization VI"
        store: steam
        steam_appid: 289070
        """
        XCTAssertEqual(
            GameProfileWriter.suggestedSteamFilename(appID: "289070", yaml: yaml),
            "steam-289070-civilization-vi.yaml"
        )
    }

    func testNewSteamProfilesShipped() {
        XCTAssertNotNil(GameProfileStore.find(steamAppID: "289070"))
        XCTAssertNotNil(GameProfileStore.find(steamAppID: "440"))
        XCTAssertNotNil(GameProfileStore.find(steamAppID: "892970"))
    }

    func testNonSteamStoreProfilesShipped() {
        let profiles = GameProfileStore.load()
        XCTAssertTrue(profiles.contains { $0.store == "itch" })
        XCTAssertTrue(profiles.contains { $0.store == "battlenet" })
        XCTAssertTrue(profiles.contains { $0.store == "standalone" })
    }

    func testMineFilterMatchesUserAuthoredOnly() {
        let user = GameProfile(
            id: "user_test",
            name: "User Test",
            store: "steam",
            gogSlug: "",
            steamAppID: "9999999",
            status: "playable",
            recommendedBackend: "dxmt",
            notes: "",
            tags: [],
            antiCheat: "",
            multiplayerNotes: "",
            dependencyCount: 0,
            fixCount: 0,
            fileURL: URL(fileURLWithPath: "/tmp/user.yaml"),
            commandRelativePath: "/tmp/user.yaml",
            isUserAuthored: true
        )
        XCTAssertTrue(CuratedProfileFilter.mine.matches(user))
        XCTAssertFalse(CuratedProfileFilter.mine.matches(GameProfileStore.find(steamAppID: "1145360")!))
    }
}
