import XCTest
@testable import Cosmos

final class GameProfileTests: XCTestCase {
    func testMultiplayerFieldsParsedFromTerrariaProfile() {
        guard let profile = GameProfileStore.find(steamAppID: "105600") else {
            XCTFail("expected terraria profile")
            return
        }
        XCTAssertTrue(profile.tags.contains("co-op"))
        XCTAssertTrue(profile.tags.contains("online"))
        XCTAssertEqual(profile.antiCheat, "none")
        XCTAssertTrue(profile.hasMultiplayerInfo)
        XCTAssertFalse(profile.multiplayerNotes.isEmpty)
    }

    func testBlockedProfileAntiCheat() {
        guard let profile = GameProfileStore.find(steamAppID: "1172470") else {
            XCTFail("expected apex legends profile")
            return
        }
        XCTAssertEqual(profile.status, "blocked")
        XCTAssertEqual(profile.antiCheat, "eac")
        XCTAssertTrue(profile.tags.contains("pvp"))
    }
}
