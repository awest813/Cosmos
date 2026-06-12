import XCTest
@testable import Cosmos

final class GameLibraryUITests: XCTestCase {
    func testLibraryStoreDetection() {
        let steam = SavedProfile(
            id: "s.conf", name: "Steam Game", path: "", args: "",
            steamAppID: "570", gogSlug: nil, fileURL: URL(fileURLWithPath: "/tmp/s.conf")
        )
        let gog = SavedProfile(
            id: "g.conf", name: "GOG Game", path: "drive_c/x", args: "",
            steamAppID: nil, gogSlug: "celeste", fileURL: URL(fileURLWithPath: "/tmp/g.conf")
        )
        XCTAssertEqual(steam.libraryStore, .steam)
        XCTAssertEqual(gog.libraryStore, .gog)
    }

    func testSourceFilterSteam() {
        let steam = SavedProfile(
            id: "s.conf", name: "Steam Game", path: "", args: "",
            steamAppID: "570", gogSlug: nil, fileURL: URL(fileURLWithPath: "/tmp/s.conf")
        )
        let manual = SavedProfile(
            id: "m.conf", name: "Manual", path: "drive_c/x.exe", args: "",
            steamAppID: nil, gogSlug: nil, fileURL: URL(fileURLWithPath: "/tmp/m.conf")
        )
        let filtered = GameLibraryFilter.filter([steam, manual], query: "", source: .steam)
        XCTAssertEqual(filtered.map(\.id), ["s.conf"])
    }

    func testSourceFilterGog() {
        let gog = SavedProfile(
            id: "g.conf", name: "GOG Game", path: "drive_c/x", args: "",
            steamAppID: nil, gogSlug: "celeste", fileURL: URL(fileURLWithPath: "/tmp/g.conf")
        )
        let filtered = GameLibraryFilter.filter([gog], query: "", source: .gog)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(GameLibrarySourceFilter.gog.matches(gog))
        XCTAssertFalse(GameLibrarySourceFilter.steam.matches(gog))
    }

    func testFilterMatchesGogSlug() {
        let profile = SavedProfile(
            id: "g.conf", name: "Celeste", path: "drive_c/x", args: "",
            steamAppID: nil, gogSlug: "celeste", fileURL: URL(fileURLWithPath: "/tmp/g.conf")
        )
        XCTAssertTrue(GameLibraryFilter.matches(profile, query: "celeste"))
        XCTAssertFalse(GameLibraryFilter.matches(profile, query: "hades"))
    }

    func testBlankSlateNewSteamWhenLibraryEmpty() {
        let kind = GameLibraryBlankSlateKind.resolve(
            totalProfiles: 0,
            filteredCount: 0,
            searchQuery: "",
            sourceFilter: .all,
            isSetupComplete: true,
            isSteamReady: true,
            pendingNewSteamGames: 2,
            pendingUnregisteredGogGames: 0
        )
        XCTAssertEqual(kind, .newSteamGames(2))
    }

    func testBlankSlateGogWhenLibraryEmpty() {
        let kind = GameLibraryBlankSlateKind.resolve(
            totalProfiles: 0,
            filteredCount: 0,
            searchQuery: "",
            sourceFilter: .all,
            isSetupComplete: true,
            isSteamReady: true,
            pendingNewSteamGames: 0,
            pendingUnregisteredGogGames: 3
        )
        XCTAssertEqual(kind, .unregisteredGog(3))
    }

    func testBlankSlateSteamTakesPriorityOverGog() {
        let kind = GameLibraryBlankSlateKind.resolve(
            totalProfiles: 0,
            filteredCount: 0,
            searchQuery: "",
            sourceFilter: .all,
            isSetupComplete: true,
            isSteamReady: true,
            pendingNewSteamGames: 1,
            pendingUnregisteredGogGames: 3
        )
        XCTAssertEqual(kind, .newSteamGames(1))
    }

    func testBlankSlateHiddenWhenProfilesExist() {
        XCTAssertNil(
            GameLibraryBlankSlateKind.resolve(
                totalProfiles: 4,
                filteredCount: 4,
                searchQuery: "",
                sourceFilter: .all,
                isSetupComplete: true,
                isSteamReady: true,
                pendingNewSteamGames: 2,
                pendingUnregisteredGogGames: 1
            )
        )
    }

    func testBlankSlateSearchEmpty() {
        let kind = GameLibraryBlankSlateKind.resolve(
            totalProfiles: 2,
            filteredCount: 0,
            searchQuery: "missing",
            sourceFilter: .all,
            isSetupComplete: true,
            isSteamReady: true,
            pendingNewSteamGames: 0,
            pendingUnregisteredGogGames: 0
        )
        XCTAssertEqual(kind, .searchEmpty("missing"))
    }

    func testBlankSlateFilterEmpty() {
        let kind = GameLibraryBlankSlateKind.resolve(
            totalProfiles: 3,
            filteredCount: 0,
            searchQuery: "",
            sourceFilter: .gog,
            isSetupComplete: true,
            isSteamReady: true,
            pendingNewSteamGames: 0,
            pendingUnregisteredGogGames: 0
        )
        XCTAssertEqual(kind, .filterEmpty(.gog))
    }
}
