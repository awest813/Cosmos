import SwiftUI

@main
struct CosmosApp: App {
    var body: some Scene {
        WindowGroup("Cosmos") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            // Cosmos manages a single dashboard window; drop the "New" menu item.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
