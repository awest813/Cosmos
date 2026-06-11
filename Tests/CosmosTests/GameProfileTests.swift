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
        XCTAssertGreaterThanOrEqual(coOp.count, 5)
        XCTAssertTrue(coOp.allSatisfy(\.hasMultiplayerInfo))
    }

    func testCoOpFilterMatchesNotesWithoutExplicitTag() {
        let profiles = GameProfileStore.load()
        let notesOnly = profiles.filter {
            !$0.tags.contains("co-op")
                && ($0.notes.localizedCaseInsensitiveContains("co-op")
                    || $0.multiplayerNotes.localizedCaseInsensitiveContains("co-op"))
        }
        XCTAssertFalse(notesOnly.isEmpty, "fixture library should include co-op titles in notes")
        XCTAssertTrue(
            notesOnly.allSatisfy { CuratedProfileFilter.coOp.matches($0) },
            "co-op filter should match notes and multiplayer_notes, not only tags"
        )
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
