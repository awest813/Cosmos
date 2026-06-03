import SwiftUI

@main
struct CosmosApp: App {
    var body: some Scene {
        WindowGroup("Cosmos") {
            ContentView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .commands {
            // Cosmos manages a single dashboard window; drop the "New" menu item.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
