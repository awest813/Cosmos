import XCTest
@testable import Cosmos

final class GameListResultTests: XCTestCase {
    func testGamesAccessor() {
        let game = SteamLibraryMonitor.DetectedGame(
            appID: "1", name: "Test", installdirOK: true, exeOK: true,
            gameExe: nil, installStatus: "ok", source: nil, syncEligible: true
        )
        let success: GameListResult<SteamLibraryMonitor.DetectedGame> = .success([game])
        XCTAssertEqual(success.games?.count, 1)

        let failure: GameListResult<SteamLibraryMonitor.DetectedGame> = .failed(exitCode: 1)
        XCTAssertNil(failure.games)
    }
}
