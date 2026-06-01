import SwiftUI

@main
struct CiderApp: App {
    @StateObject private var engine = CiderEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 700, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
