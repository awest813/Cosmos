import Foundation

/// Cross-view notifications for the menu bar and dashboard chrome.
extension Notification.Name {
    static let cosmosRefreshStatus = Notification.Name("com.cosmos.refreshStatus")
    static let cosmosContinueSetup = Notification.Name("com.cosmos.continueSetup")
    static let cosmosOpenSetupHelp = Notification.Name("com.cosmos.openSetupHelp")
    static let cosmosSelectSection = Notification.Name("com.cosmos.selectSection")
    static let cosmosSyncSteamLibrary = Notification.Name("com.cosmos.syncSteamLibrary")
    static let cosmosSyncGogLibrary = Notification.Name("com.cosmos.syncGogLibrary")
    static let cosmosSyncGogLibraryBuild = Notification.Name("com.cosmos.syncGogLibraryBuild")
    static let cosmosBuildLaunchers = Notification.Name("com.cosmos.buildLaunchers")
    static let cosmosDetectSteamGames = Notification.Name("com.cosmos.detectSteamGames")
    static let cosmosLaunchSelectedGame = Notification.Name("com.cosmos.launchSelectedGame")
    static let cosmosLaunchSteam = Notification.Name("com.cosmos.launchSteam")
    static let cosmosVerifySteam = Notification.Name("com.cosmos.verifySteam")
    static let cosmosListGogGames = Notification.Name("com.cosmos.listGogGames")
    static let cosmosOpenLogs = Notification.Name("com.cosmos.openLogs")
    static let cosmosCheckForUpdates = Notification.Name("com.cosmos.checkForUpdates")
    static let cosmosRunDiagnose = Notification.Name("com.cosmos.runDiagnose")
    static let cosmosOpenImportTools = Notification.Name("com.cosmos.openImportTools")
}
