import SwiftUI

@main
struct CosmosApp: App {
    var body: some Scene {
        WindowGroup("Cosmos") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1040, height: 720)
        .windowStyle(.titleBar)
        .commands {
            // Cosmos manages a single dashboard window; drop the "New" menu item.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .sidebar) {
                Button("Refresh Status") {
                    NotificationCenter.default.post(name: .cosmosRefreshStatus, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
