import SwiftUI

@main
struct CosmosApp: App {
    var body: some Scene {
        WindowGroup("Cosmos") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.titleBar)
        .commands {
            // Cosmos manages a single dashboard window; drop the "New" menu item.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Continue Setup") {
                    NotificationCenter.default.post(name: .cosmosContinueSetup, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Refresh Status") {
                    NotificationCenter.default.post(name: .cosmosRefreshStatus, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Steam Setup Guide") {
                    NotificationCenter.default.post(name: .cosmosOpenSetupHelp, object: nil)
                }
            }
        }
    }
}
