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
        XCTAssertTrue(profile.isBlocked)
        XCTAssertTrue(profile.blockedLaunchMessage.contains("blocked"))
    }

    func testCuratedProfileFilterCoOp() {
        let profiles = GameProfileStore.load()
        let coOp = profiles.filter { CuratedProfileFilter.coOp.matches($0) }
        XCTAssertGreaterThan(coOp.count, 10)
        XCTAssertTrue(coOp.allSatisfy(\.hasMultiplayerInfo)
    }

    func testCuratedProfileFilterBlocked() {
        let profiles = GameProfileStore.load()
        let blocked = profiles.filter { CuratedProfileFilter.blocked.matches($0) }
        XCTAssertGreaterThan(blocked.count, 20)
        XCTAssertTrue(blocked.allSatisfy(\.isBlocked))
    }

    func testProfilesWithFixesReachTarget() {
        let withFixes = GameProfileStore.load().filter { $0.fixCount > 0 }
        XCTAssertGreaterThanOrEqual(withFixes.count, 30, "Phase D target: 30+ profiles with fixes")
    }
}
