import XCTest
@testable import Cosmos

final class CosmosMenuCommandsTests: XCTestCase {
    func testMenuNotificationNamesAreUnique() {
        let names: [Notification.Name] = [
            .cosmosRefreshStatus,
            .cosmosContinueSetup,
            .cosmosOpenSetupHelp,
            .cosmosSelectSection,
            .cosmosSyncSteamLibrary,
            .cosmosSyncGogLibrary,
            .cosmosSyncGogLibraryBuild,
            .cosmosBuildLaunchers,
            .cosmosDetectSteamGames,
        ]
        let raw = names.map(\.rawValue)
        XCTAssertEqual(Set(raw).count, raw.count)
    }
}
