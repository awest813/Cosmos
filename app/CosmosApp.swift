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
            CommandGroup(after: .sidebar) {
                Button(appState.isSetupComplete ? "Refresh Status" : "Continue Setup") {
                    if appState.isSetupComplete {
                        NotificationCenter.default.post(name: .cosmosRefreshStatus, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .cosmosContinueSetup, object: nil)
                    }
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
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
                Button("Tools") {
                    NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.tools)
                }
                .keyboardShortcut("3", modifiers: .command)
                Button("Bottles") {
                    NotificationCenter.default.post(name: .cosmosSelectSection, object: DashboardSection.bottles)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Steam Setup Guide") {
                    NotificationCenter.default.post(name: .cosmosOpenSetupHelp, object: nil)
                }
            }
        }
    }
}
