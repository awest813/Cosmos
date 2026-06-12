import SwiftUI

@main
struct CosmosApp: App {
    @ObservedObject private var appState = CosmosAppState.shared

    var body: some Scene {
        WindowGroup("Cosmos") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // Cosmos manages a single dashboard window; drop the "New" menu item.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandMenu("Game") {
                Button("Launch Selected Game") {
                    NotificationCenter.default.post(name: .cosmosLaunchSelectedGame, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!appState.canLaunchSelectedProfile || !appState.canAcceptCommands)
                Button("Launch Steam") {
                    NotificationCenter.default.post(name: .cosmosLaunchSteam, object: nil)
                }
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
            }
            CommandGroup(after: .sidebar) {
                Button("Continue Setup") {
                    NotificationCenter.default.post(name: .cosmosContinueSetup, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(appState.isSetupComplete)
                Button("Refresh Status") {
                    NotificationCenter.default.post(name: .cosmosRefreshStatus, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Dashboard") {
                Button("Launch") {
                    NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.launch)
                }
                .keyboardShortcut("1", modifiers: .command)
                Button("Games") {
                    NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.library)
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!appState.isSetupComplete)
                Button("Tools") {
                    NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.tools)
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!appState.isSetupComplete)
                Button("Bottles") {
                    NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.bottles)
                }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(!appState.isSetupComplete)
            }
            CommandMenu("Library") {
                Button("Sync Steam Library…") {
                    NotificationCenter.default.post(name: .cosmosSyncSteamLibrary, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Button("Register GOG Games…") {
                    NotificationCenter.default.post(name: .cosmosSyncGogLibrary, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Button("Register GOG + Build Launchers") {
                    NotificationCenter.default.post(name: .cosmosSyncGogLibraryBuild, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Divider()
                Button("Build Launchers") {
                    NotificationCenter.default.post(name: .cosmosBuildLaunchers, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Button("Detect Steam Games") {
                    NotificationCenter.default.post(name: .cosmosDetectSteamGames, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Button("List GOG Games") {
                    NotificationCenter.default.post(name: .cosmosListGogGames, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Button("Verify Steam Library") {
                    NotificationCenter.default.post(name: .cosmosVerifySteam, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Divider()
                Button("Import Non-Steam Game…") {
                    NotificationCenter.default.post(name: .cosmosOpenImportTools, object: nil)
                }
                .disabled(!appState.isSetupComplete)
            }
            CommandMenu("Tools") {
                Button("Verify Steam Library") {
                    NotificationCenter.default.post(name: .cosmosVerifySteam, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Button("Run Diagnostics") {
                    NotificationCenter.default.post(name: .cosmosRunDiagnose, object: nil)
                }
                .disabled(!appState.isSetupComplete || !appState.canAcceptCommands)
                Divider()
                Button("Open Latest Log") {
                    NotificationCenter.default.post(name: .cosmosOpenLogs, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)
                Button("Check for Updates") {
                    NotificationCenter.default.post(name: .cosmosCheckForUpdates, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Steam Setup Guide") {
                    NotificationCenter.default.post(name: .cosmosOpenSetupHelp, object: nil)
                }
                Button("Open Latest Log") {
                    NotificationCenter.default.post(name: .cosmosOpenLogs, object: nil)
                }
            }
        }
    }
}
