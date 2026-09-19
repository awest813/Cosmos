import SwiftUI

@main
struct CosmosApp: App {
    private let appState = CosmosAppState.shared

    var body: some Scene {
        WindowGroup("Cosmos") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands { CosmosCommands(appState: appState) }
    }
}

/// Observe availability in the menus, without rebuilding the WindowGroup when
/// a command starts or finishes.
private struct CosmosCommands: Commands {
    @ObservedObject var appState: CosmosAppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}

        // Setup → play: launch actions first.
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
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Divider()
            Button("Show in Game Library") {
                NotificationCenter.default.post(name: .cosmosShowSelectedInLibrary, object: nil)
            }
            .disabled(!appState.hasSelectedProfile || !appState.isSteamReady)
            Button("Show on Launch Tab") {
                NotificationCenter.default.post(name: .cosmosShowSelectedOnLaunch, object: nil)
            }
            .disabled(!appState.hasSelectedProfile || !appState.isSteamReady)
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

        // Dashboard tabs mirror the in-app tab bar (⌘1–4).
        CommandMenu("Dashboard") {
            Button("Launch") {
                NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.launch)
            }
            .keyboardShortcut("1", modifiers: .command)
            Button("Games") {
                NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.library)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(!appState.isSteamReady)
            Button("Tools") {
                NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.tools)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(!appState.isSteamReady)
            Button("Bottles") {
                NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.bottles)
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(!appState.isSteamReady)
        }

        // Steam prefix, graphics, and bottles.
        CommandMenu("Settings") {
            Button("Downloads…") {
                NotificationCenter.default.post(name: .cosmosOpenDownloads, object: nil)
            }
            Divider()
            Button("Steam & Wine…") {
                NotificationCenter.default.post(name: .cosmosOpenSteamSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(!appState.isSteamReady)
            Button("Performance & Graphics…") {
                NotificationCenter.default.post(name: .cosmosOpenPerformanceGraphics, object: nil)
            }
            .disabled(!appState.isSteamReady)
            Divider()
            Button("Bottles…") {
                NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.bottles)
            }
            .disabled(!appState.isSteamReady)
            Divider()
            Button("Reveal steam.conf in Finder") {
                NotificationCenter.default.post(name: .cosmosRevealSteamConf, object: nil)
            }
            .disabled(!appState.isSteamReady)
            Button("Graphics Backends Guide…") {
                NotificationCenter.default.post(name: .cosmosOpenBackendsGuide, object: nil)
            }
        }

        // Saved launchers: sync, detect, import.
        CommandMenu("Library") {
            Button("Add All New Games…") {
                NotificationCenter.default.post(name: .cosmosSyncAllLibrary, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("Add New Steam Games…") {
                NotificationCenter.default.post(name: .cosmosSyncSteamLibrary, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("Add GOG Games…") {
                NotificationCenter.default.post(name: .cosmosSyncGogLibrary, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("Add GOG Games & Dock Shortcuts") {
                NotificationCenter.default.post(name: .cosmosSyncGogLibraryBuild, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Divider()
            Button("Create Dock Shortcuts") {
                NotificationCenter.default.post(name: .cosmosBuildLaunchers, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("Preview Detected Steam Games") {
                NotificationCenter.default.post(name: .cosmosDetectSteamGames, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Divider()
            Button("Add Game Preset…") {
                NotificationCenter.default.post(name: .cosmosAddGameProfile, object: nil)
            }
            .disabled(!appState.isSteamReady)
            Button("Import Non-Steam Game…") {
                NotificationCenter.default.post(name: .cosmosOpenImportTools, object: nil)
            }
            .disabled(!appState.isSteamReady)
        }

        // Maintenance, diagnostics, logs.
        CommandMenu("Tools") {
            Button("Run Diagnostics") {
                NotificationCenter.default.post(name: .cosmosRunDiagnose, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("Verify Steam Library") {
                NotificationCenter.default.post(name: .cosmosVerifySteam, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("List GOG Games") {
                NotificationCenter.default.post(name: .cosmosListGogGames, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
            Button("Apply Installed Profiles") {
                NotificationCenter.default.post(name: .cosmosApplyInstalledProfiles, object: nil)
            }
            .disabled(!appState.isSteamReady || !appState.canAcceptCommands)
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
            if !appState.isSetupComplete {
                Button("Continue Setup") {
                    NotificationCenter.default.post(name: .cosmosContinueSetup, object: nil)
                }
                Divider()
            }
            Button("Steam Setup Guide") {
                NotificationCenter.default.post(name: .cosmosOpenSetupHelp, object: nil)
            }
            Button("Open Latest Log") {
                NotificationCenter.default.post(name: .cosmosOpenLogs, object: nil)
            }
        }
    }
}
