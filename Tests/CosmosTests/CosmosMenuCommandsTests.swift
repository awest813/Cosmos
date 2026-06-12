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
            .cosmosLaunchSelectedGame,
            .cosmosLaunchSteam,
            .cosmosVerifySteam,
            .cosmosListGogGames,
            .cosmosOpenLogs,
            .cosmosCheckForUpdates,
            .cosmosRunDiagnose,
            .cosmosOpenImportTools,
        ]
        let raw = names.map(\.rawValue)
        XCTAssertEqual(Set(raw).count, raw.count)
    }
}
